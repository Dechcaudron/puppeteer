module puppeteer.communication.communicator;

import puppeteer.puppeteer;
import puppeteer.var_monitor_utils;

import puppeteer.communication.communicator_messages;
import puppeteer.communication.communication_exception;
import puppeteer.communication.is_communicator;

import puppeteer.puppet_link.puppet_link;
import puppeteer.puppet_link.is_puppet_link;

import std.stdio;
import std.exception;
import std.concurrency;
import std.datetime;
import std.conv;
import std.meta;

import core.thread;
import core.atomic;

shared class Communicator(IVTypes...)
{
    static assert(isCommunicator!(shared typeof(this), IVTypes));

    /* Ugly fix for allowing different instances */

    static int next_id = 0;
    private int id;

    @property
    private string workerTidName()
    {
        enum nameBase = "valueEmitter.communicator";

        return nameBase ~ to!string(id);
    }

    @property
    private Tid workerTid()
    {
        return locate(workerTidName);
    }

    /* End of ugly fix */

    private OnAIUpdateCallback onAIUpdateCallback;

    // Generate onIVUpdateCallback fields for IVTypes
    private mixin(unrollOnIVUpdateCallbackFields!IVTypes());

    // Alias the previous fields
    alias onIVUpdateCallback(IVType) = Alias!(mixin(onIVUpdateCallbackFieldName!IVType));

    @property
    public bool isCommunicationOngoing()
    {
        return workerTid != Tid.init;
    }

    private void enforceCommunicationOngoing()
    {
        enforce(isCommunicationOngoing);
    }

    this()
    {
        id = next_id++;
    }

    public final bool startCommunication(PuppetLinkT = PuppetLink!(shared typeof(this),
                                                             shared typeof(this),
                                                             IVTypes))
                                                             (string devFilename,
                                                             BaudRate baudRate,
                                                             Parity parity,
                                                             string logFilename)
    if(isPuppetLink!(PuppetLinkT, shared typeof(this), shared typeof(this)))
    {
        enforce!CommunicationException(!isCommunicationOngoing);

        auto workerTid = spawn(&communicationLoop!PuppetLinkT, devFilename, baudRate, parity, logFilename);
        register(workerTidName, workerTid);

        auto msg = receiveOnly!CommunicationEstablishedMessage();

        return msg.success;
    }

    public void endCommunication()
    {
        enforceCommunicationOngoing();

        workerTid.send(EndCommunicationMessage());
        receiveOnly!CommunicationEndedMessage();
    }

    public void setAIMonitor(ubyte pin, bool shouldMonitor)
    {
        enforceCommunicationOngoing();
        workerTid.send(PinMonitorMessage(shouldMonitor ?
                                            PinMonitorMessage.Action.start :
                                            PinMonitorMessage.Action.stop, pin));
    }

    public void setIVMonitor(IVType)(ubyte varIndex, bool shouldMonitor)
    if(staticIndexOf!(IVType, IVTypes) != -1)
    {
        enforceCommunicationOngoing();
        workerTid.send(VarMonitorMessage(shouldMonitor ?
                                            VarMonitorMessage.Action.start :
                                            VarMonitorMessage.Action.stop,
                                            varIndex,
                                            varMonitorTypeCode!IVType));
    }

    public void setOnAIUpdateCallback(OnAIUpdateCallback callback)
    {
        onAIUpdateCallback = callback;
    }

    public void setOnIVUpdateCallback(IVType)(OnIVUpdateCallback!IVType callback)
    {
        onIVUpdateCallback!IVType = callback;
    }

    public void setPWMValue(ubyte pin, ubyte pwmValue)
    {
        enforceCommunicationOngoing();
        workerTid.send(SetPWMMessage(pin, pwmValue));
    }

    private void communicationLoop(PuppetLinkT)(string fileName, immutable BaudRate baudRate, immutable Parity parity, string logFilename)
    if(isPuppetLink!(PuppetLinkT, shared typeof(this), shared typeof(this)))
    {
        enum receiveTimeoutMs = 10;
        enum bytesReadAtOnce = 1;

        PuppetLinkT puppetLink = new PuppetLinkT(fileName);
        puppetLink.AIMonitorListener = this;
        puppetLink.IVMonitorListener = this;

        if(puppetLink.startCommunication())
            ownerTid.send(CommunicationEstablishedMessage(true));
        else
        {
            ownerTid.send(CommunicationEstablishedMessage(false));
            return;
        }

        StopWatch communicationStopWatch = StopWatch(AutoStart.yes);

        bool shouldContinue = true;

        do
        {
            puppetLink.readPuppet(communicationStopWatch.peek().msecs);

            receiveTimeout(msecs(receiveTimeoutMs),
                    (EndCommunicationMessage msg)
                    {
                        shouldContinue = false;
                    },
                    (PinMonitorMessage msg)
                    {
                        puppetLink.setAIMonitor(msg.pin, msg.action == PinMonitorMessage.Action.start);
                    },
                    (VarMonitorMessage msg)
                    {
                        puppetLink.setIVMonitor(msg.varTypeCode, msg.varIndex, msg.action == VarMonitorMessage.Action.start);
                    },
                    (SetPWMMessage msg)
                    {
                        puppetLink.setPWMOut(msg.pin, msg.value);
                    });

        }while(shouldContinue);

        puppetLink.endCommunication();
        communicationStopWatch.stop();

        ownerTid.send(CommunicationEndedMessage());
    }

    void onAIUpdate(ubyte pin, float value, long communicationMillisTime)
    {
        enforce(isCommunicationOngoing);

        if(onAIUpdateCallback !is typeof(onAIUpdateCallback).init)
            onAIUpdateCallback(pin, value, communicationMillisTime);
    }

    void onIVUpdate(IVType)(ubyte varIndex, IVType value, long communicationMillisTime)
    if(staticIndexOf!(IVType, IVTypes) !is -1)
    {
        enforce(isCommunicationOngoing);

        if(onIVUpdateCallback!IVType !is typeof(onIVUpdateCallback!IVType).init)
            onIVUpdateCallback!IVType(varIndex, value, communicationMillisTime);
    }
}

private enum onIVUpdateCallbackFieldName(T) = format("_onIVUpdateCallback__Communicator_Internal_%s", T.stringof);

private pure string unrollOnIVUpdateCallbackFields(Ts...)()
{
    string str = "";
    foreach(T; Ts)
        str ~= format("OnIVUpdateCallback!%s %s;\n",
                        T.stringof, onIVUpdateCallbackFieldName!T);

    return str;
}
