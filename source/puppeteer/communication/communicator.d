module puppeteer.communication.communicator;

import puppeteer.puppeteer;
import puppeteer.var_monitor_utils;

import puppeteer.communication.icommunicator;
import puppeteer.communication.communicator_messages;
import puppeteer.communication.communication_exception;

import std.stdio;
import std.exception;
import std.concurrency;
import std.datetime;
import std.conv;

import core.thread;
import core.atomic;

shared class Communicator(IVTypes...) : ICommunicator!IVTypes
{
    static int next_id = 0;
    private int id;

    @property
    private string workerTidName()
    {
        enum nameBase = "puppeteer.communicator";

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

    protected Puppeteer!IVTypes connectedPuppeteer;

    this()
    {
        id = next_id++;
    }

    public bool startCommunication(shared Puppeteer!IVTypes puppeteer, string devFilename, BaudRate baudRate, Parity parity, string logFilename)
    {
        enforce!CommunicationException(!isCommunicationOngoing);

        connectedPuppeteer = puppeteer;

        auto workerTid = spawn(&communicationLoop, devFilename, baudRate, parity, logFilename);
        register(workerTidName, workerTid);

        auto msg = receiveOnly!CommunicationEstablishedMessage();

        if(!msg.success)
            connectedPuppeteer = null;

        return msg.success;
    }

    public void endCommunication()
    {
        enforceCommunicationOngoing();

        workerTid.send(EndCommunicationMessage());
        receiveOnly!CommunicationEndedMessage();

        connectedPuppeteer = null;
    }

    public void changeAIMonitorStatus(ubyte pin, bool shouldMonitor)
    {
        enforceCommunicationOngoing();
        workerTid.send(PinMonitorMessage(shouldMonitor ?
                                            PinMonitorMessage.Action.start :
                                            PinMonitorMessage.Action.stop, pin));
    }

    mixin(unrollChangeVarMonitorStatusMethods!IVTypes);
    public void changeVarMonitorStatus(VarType)(ubyte varIndex, bool shouldMonitor)
    {
        enforceCommunicationOngoing();
        workerTid.send(VarMonitorMessage(shouldMonitor ?
                                            VarMonitorMessage.Action.start :
                                            VarMonitorMessage.Action.stop,
                                            varIndex,
                                            varMonitorTypeCode!VarType));
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

        if(puppetLink.startCommunication())
            ownerTid.send(CommunicationEstablishedMessage(true));
        else
        {
            ownerTid.send(CommunicationEstablishedMessage(false));
            return;
        }

        StopWatch timer;

        void handleReadBytes(ubyte[] readBytes)
        in
        {
            assert(readBytes !is null);
            assert(readBytes.length != 0);
        }
        body
        {
            void handleAnalogMonitorCommand(ubyte[] command)
            in
            {
                assert(command !is null);
                assert(command.length == 4);
                assert(command[0] == ReadCommands.analogMonitor);
            }
            body
            {
                long readMilliseconds = timer.peek().msecs;

                debug(2) writeln("Handling analogMonitorCommand ", command);

                ubyte pin = command[1];

                enum arduinoAnalogReadMax = 1023;
                enum arduinoAnalogReference = 5;
                enum ubytePossibleValues = 256;

                ushort encodedValue = command[2] * ubytePossibleValues + command[3];
                float readValue =  arduinoAnalogReference * to!float(encodedValue) / arduinoAnalogReadMax;

                connectedPuppeteer.emitAIRead(pin, readValue, readMilliseconds);
            }

            void handleVarMonitorCommand(ubyte[] command)
            in
            {
                assert(command !is null);
                assert(command.length == 5);
                assert(command[0] == ReadCommands.varMonitor);
            }
            body
            {
                long readMilliseconds = timer.peek().msecs;
                debug(2) writeln("Handling varMonitorCommand ", command);

                void handleData(VarType)(ubyte varIndex, ubyte[] data)
                if(connectedPuppeteer.canMonitor!VarType)
                {
                    VarType decodeData(VarType : short)(ubyte[] data) pure
                    {
                        enum ubytePossibleValues = 256;
                        return to!short(data[0] * ubytePossibleValues + data[1]);
                    }

                    auto receivedData = decodeData!VarType(data);

                    connectedPuppeteer.emitVarRead!VarType(varIndex, receivedData, timer.peek().msecs);
                }

                void delegate (ubyte, ubyte[]) selectDelegate(VarMonitorTypeCode typeCode)
                {
                    string generateSwitch()
                    {
                        string str = "switch (typeCode) with (VarMonitorTypeCode) {";

                        foreach(varType; IVTypes)
                        {
                            str ~= "case " ~ to!string(varMonitorTypeCode!varType) ~ ": return &handleData!" ~ varType.stringof ~ ";";
                        }

                        str ~= "default: return null; }" ;

                        return str;
                    }

                    mixin(generateSwitch());
                }

                try
                {
                    auto handler = selectDelegate(to!VarMonitorTypeCode(command[1]));
                    if(handler)
                        handler(command[2], command[3..$]);
                }catch(ConvException e)
                {
                    writeln("Received invalid varMonitor type: ",e);
                }
            }

        timer.start();

        bool shouldContinue = true;

        do
        {
            puppetLink.readPuppet();

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

        ownerTid.send(CommunicationEndedMessage());
    }
}
