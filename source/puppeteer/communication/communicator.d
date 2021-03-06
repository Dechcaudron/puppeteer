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

shared class Communicator(PuppetLinkT, IVTypes...)
if(isPuppetLink!(PuppetLinkT, IVTypes))
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

    private Tuple!(staticMap!(OnIVUpdateCallback, IVTypes)) onIVUpdateCallbacks;
    alias onIVUpdateCallback(IVType) = onIVUpdateCallbacks[staticIndexOf!(IVType, IVTypes)];

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

    bool startCommunication(string devFilename, BaudRate baudRate, Parity parity)
    {
        enforce!CommunicationException(!isCommunicationOngoing);

        auto workerTid = spawn(&communicationLoop!PuppetLinkT, devFilename, baudRate, parity);
        register(workerTidName, workerTid);

        auto msg = receiveOnly!CommunicationEstablishedMessage();

        return msg.success;
    }

    void endCommunication()
    {
        enforceCommunicationOngoing();

        workerTid.send(EndCommunicationMessage());
        receiveOnly!CommunicationEndedMessage();
    }

    void setAIMonitor(ubyte pin, bool shouldMonitor)
    {
        enforceCommunicationOngoing();
        workerTid.send(PinMonitorMessage(shouldMonitor ?
                                            PinMonitorMessage.Action.start :
                                            PinMonitorMessage.Action.stop, pin));
    }

    void setIVMonitor(IVType)(ubyte varIndex, bool shouldMonitor)
    if(staticIndexOf!(IVType, IVTypes) != -1)
    {
        enforceCommunicationOngoing();
        workerTid.send(VarMonitorMessage(shouldMonitor ?
                                            VarMonitorMessage.Action.start :
                                            VarMonitorMessage.Action.stop,
                                            varIndex,
                                            varMonitorTypeCode!IVType));
    }

    void setOnAIUpdateCallback(OnAIUpdateCallback callback)
    {
        onAIUpdateCallback = callback;
    }

    void setOnIVUpdateCallback(IVType)(OnIVUpdateCallback!IVType callback)
    {
        onIVUpdateCallback!IVType = callback;
    }

    void setPWMValue(ubyte pin, ubyte pwmValue)
    {
        enforceCommunicationOngoing();
        workerTid.send(SetPWMMessage(pin, pwmValue));
    }

    private void communicationLoop(string fileName,
                                   immutable BaudRate baudRate,
                                   immutable Parity parity)
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
