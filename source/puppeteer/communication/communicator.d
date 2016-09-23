module puppeteer.communication.communicator;

import puppeteer.puppeteer;
import puppeteer.var_monitor_utils;

import puppeteer.communication.icommunicator;
import puppeteer.communication.communicator_messages;
import puppeteer.communication.communication_exception;
import puppeteer.communication.is_value_emitter;

import std.stdio;
import std.exception;
import std.concurrency;
import std.datetime;
import std.conv;
import std.meta;

import core.thread;
import core.atomic;

shared class Communicator(ValueEmitterT, IVTypes...)
{
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

    @property
    public bool isCommunicationOngoing()
    {
        return workerTid != Tid.init;
    }

    private void enforceCommunicationOngoing()
    {
        enforce(isCommunicationOngoing);
    }

    protected ValueEmitterT connectedValueEmitter;

    this()
    {
        id = next_id++;
    }

    public bool startCommunication(ValueEmitterT, PuppetLinkT = PuppetLink)(shared ValueEmitterT valueEmitter,
                                                                            string devFilename,
                                                                            BaudRate baudRate,
                                                                            Parity parity,
                                                                            string logFilename)
    if(isValueEmitter!(ValueEmitterT, IVTypes) && isPuppetLink!PuppetLinkT)
    {
        enforce!CommunicationException(!isCommunicationOngoing);

        connectedValueEmitter = valueEmitter;

        auto workerTid = spawn(&communicationLoop!PuppetLinkT, devFilename, baudRate, parity, logFilename);
        register(workerTidName, workerTid);

        auto msg = receiveOnly!CommunicationEstablishedMessage();

        if(!msg.success)
            connectedValueEmitter = ValueEmitterT.init;

        return msg.success;
    }

    public void endCommunication()
    {
        enforceCommunicationOngoing();

        workerTid.send(EndCommunicationMessage());
        receiveOnly!CommunicationEndedMessage();

        connectedValueEmitter = ValueEmitterT.init;
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

    public void setPWMValue(ubyte pin, ubyte pwmValue)
    {
        enforceCommunicationOngoing();
        workerTid.send(SetPWMMessage(pin, pwmValue));
    }

    private void communicationLoop(PuppetLinkT)(string fileName, immutable BaudRate baudRate, immutable Parity parity, string logFilename)
    if(isPuppetLink!(PuppetLinkT, IVTypes))
    {
        enum receiveTimeoutMs = 10;
        enum bytesReadAtOnce = 1;

        IPuppetLink puppetLink = new PuppetLinkT(fileName);
        puppetLink.AIMonitorListener = this;
        puppetLink.IVMonitorListener = this;

        if(puppetLink.startCommunication())
            ownerTid.send(CommunicationEstablishedMessage(true));
        else
        {
            ownerTid.send(CommunicationEstablishedMessage(false));
            return;
        }

        StopWatch communicationStopWatch(AutoStart.yes);

        bool shouldContinue = true;

        do
        {
            puppetLink.readPuppet(communicationStopWatch.peek());

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
                        puppetLink.setIVMonitor(msg.varIndex, msg.varTypeCode, msg.action == VarMonitorMessage.Action.start);
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
        connectedValueEmitter.emitAIRead(pin, value, communicationMillisTime);
    }

    void onIVUpdate(IVType)(ubyte varIndex, IVType value, long communicationMillisTime)
    if(staticIndexOf!(IVType, IVTypes))
    {
        enforce(isCommunicationOngoing);
        connectedValueEmitter.emitVarRead!IVType(varIndex, value, communicationMillisTime);
    }
}
