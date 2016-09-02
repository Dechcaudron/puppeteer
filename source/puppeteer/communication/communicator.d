module puppeteer.communication.communicator;

import puppeteer.puppeteer;
import puppeteer.var_monitor_utils;

import puppeteer.logging.ipuppeteer_logger;

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

shared class Communicator(VarMonitorTypes...) : ICommunicator!VarMonitorTypes
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

    protected Puppeteer!VarMonitorTypes connectedPuppeteer;

    this()
    {
        id = next_id++;
    }

    public bool startCommunication(shared Puppeteer!VarMonitorTypes puppeteer, string devFilename, BaudRate baudRate, Parity parity, string logFilename)
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
        workerTid.send(PinMonitorMessage(shouldMonitor ? PinMonitorMessage.Action.start : PinMonitorMessage.Action.stop, pin));
    }

    mixin(unrollChangeVarMonitorStatusMethods!VarMonitorTypes);
    public void changeVarMonitorStatus(VarType)(ubyte varIndex, bool shouldMonitor)
    {
        enforceCommunicationOngoing();
        workerTid.send(VarMonitorMessage(shouldMonitor ? VarMonitorMessage.Action.start : VarMonitorMessage.Action.stop,
                                         varIndex, getVarMonitorTypeCode!VarType));
    }

    public void setPWMValue(ubyte pin, ubyte pwmValue)
    {
        enforceCommunicationOngoing();
        workerTid.send(SetPWMMessage(pin, pwmValue));
    }

    private void communicationLoop(string fileName, immutable BaudRate baudRate, immutable Parity parity, string logFilename)
    {
        enum receiveTimeoutMs = 10;
        enum bytesReadAtOnce = 1;

        enum ubyte commandControlByte = 0xff;

        bool shouldContinue = true;

        ISerialPort arduinoSerialPort;
        IPuppeteerLogger logger;
        scope(exit) destroy(logger);

        void handlePinMonitorMessage(PinMonitorMessage msg)
        {
            void sendStartMonitoringPinCmd(ISerialPort serialPort, ubyte pin)
            {
                debug writeln("Sending startMonitoringCommand for pin "~to!string(pin));
                serialPort.write([commandControlByte, 0x01, pin]);
            }

            void sendStopMonitoringPinCmd(ISerialPort serialPort, ubyte pin)
            {
                debug writeln("Sending stopMonitoringCommand for pin "~to!string(pin));
                serialPort.write([commandControlByte, 0x02, pin]);
            }

            final switch(msg.action) with (PinMonitorMessage.Action)
            {
                case start:
                    sendStartMonitoringPinCmd(arduinoSerialPort, msg.pin);
                    break;

                case stop:
                    sendStopMonitoringPinCmd(arduinoSerialPort, msg.pin);
                    break;
            }
        }

        void handleEndCommunicationMessage(EndCommunicationMessage msg)
        {
            shouldContinue = false;
        }

        void handleVarMonitorMessage(VarMonitorMessage msg)
        {
            void sendStartMonitoringVariableCmd(ISerialPort serialPort, VarMonitorTypeCode typeCode, byte varIndex)
            {
                debug writeln("Sending startMonitoringVariableCommand for type ", typeCode, " and index ", varIndex);
                serialPort.write([commandControlByte, 0x05, typeCode, varIndex]);
            }

            void sendStopMonitoringVariableCmd(ISerialPort serialPort, VarMonitorTypeCode typeCode, byte varIndex)
            {
                debug writeln("Sending stopMonitoringVariableCommand for type ", typeCode, " and index ", varIndex);
                serialPort.write([commandControlByte, 0x06, typeCode, varIndex]);
            }

            final switch(msg.action) with (VarMonitorMessage.Action)
            {
                case start:
                    sendStartMonitoringVariableCmd(arduinoSerialPort, msg.varTypeCode, msg.varIndex);
                    break;

                case stop:
                    sendStopMonitoringVariableCmd(arduinoSerialPort, msg.varTypeCode, msg.varIndex);
                    break;
            }
        }

        void handleSetPWMMessage(SetPWMMessage msg)
        {
            void sendSetPWMCmd(ISerialPort serialPort, ubyte pin, ubyte value)
            {
                debug writeln("Sending setPWMCommand for pin "~to!string(pin)~" and value "~to!string(value));
                serialPort.write([commandControlByte, 0x04, pin, value]);
            }

            sendSetPWMCmd(arduinoSerialPort, msg.pin, msg.value);
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
            enum ReadCommands : ubyte
            {
                analogMonitor = 0x1,
                varMonitor = 0x2,
                error = 0xfe
            }

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

                        foreach(varType; VarMonitorTypes)
                        {
                            str ~= "case " ~ (getVarMonitorTypeCode!varType).stringof ~ ": return &handleData!" ~ varType.stringof ~ ";";
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

            static ubyte[] readBuffer = [];

            readBuffer ~= readBytes;

            void popReadBuffer(size_t elements = 1)
            {
                readBuffer = readBuffer.length >= elements ? readBuffer[elements..$] : [];
            }

            if(readBuffer[0] != commandControlByte)
            {
                debug writeln("Received corrupt command. Discarding first byte and returning");
                popReadBuffer();
                return;
            }

            if(readBuffer.length < 2)
                return;

            //Try to make sense out of the readBytes
            switch(readBuffer[1])
            {
                case ReadCommands.analogMonitor:
                    if(readBuffer.length < 5)
                        return;

                    handleAnalogMonitorCommand(readBuffer[1..5]);
                    popReadBuffer(5);
                    break;

                case ReadCommands.varMonitor:
                    if(readBuffer.length < 6)
                        return;

                    handleVarMonitorCommand(readBuffer[1..6]);
                    popReadBuffer(6);
                    break;

                case ReadCommands.error:
                    writeln("Error received!");
                    break;

                default:
                    writeln("Unhandled ubyte command received: ", readBuffer[0], ". Cleaning command buffer.");
                    readBuffer = [];
            }
        }

        enum portReadTimeoutMs = 200;
        arduinoSerialPort = ISerialPort.getInstance(fileName, parity, baudRate, portReadTimeoutMs);
        if(!arduinoSerialPort.open())
        {
            ownerTid.send(CommunicationEstablishedMessage(false));
            return;
        }

        //Some puppets seems to need some time between port opening and communication start
        Thread.sleep(dur!"seconds"(1));

        enum ubyte[] puppeteerReadyCommand = [0x0, 0x0];
        arduinoSerialPort.write([commandControlByte] ~ puppeteerReadyCommand);

        //Wait for the puppet to answer it is ready
        {
            enum ubyte[] puppetReadyCommand = [0x0, 0x0];
            ubyte[] cache = [];
            enum msBetweenChecks = 100;

            int readCounter = 0;
            enum readsUntilFailure = 30;

            while(true)
            {
                ubyte[] readBytes = arduinoSerialPort.read(1);

                if(readBytes !is null)
                {
                    cache ~= readBytes;
                    debug writeln("handshake cache is currently ", cache);

                    if(cache.length == 3)
                    {
                        if(cache == [commandControlByte] ~ puppetReadyCommand)
                            break; //Ready!
                        else
                            cache = cache[1..$]; //pop front and continue
                    }
                }

                if(++readCounter > readsUntilFailure)
                {
                    ownerTid.send(CommunicationEstablishedMessage(false));
                    return;
                }

                Thread.sleep(dur!"msecs"(msBetweenChecks));
            }
        }

        ownerTid.send(CommunicationEstablishedMessage(true));
        timer.start();

        do
        {
            ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

            if(readBytes !is null)
            {
                debug(3) writeln("Read bytes ", readBytes);
                handleReadBytes(readBytes);
            }

            receiveTimeout(msecs(receiveTimeoutMs), &handleEndCommunicationMessage,
                    &handlePinMonitorMessage,
                    &handleVarMonitorMessage,
                    &handleSetPWMMessage);

        }while(shouldContinue);

        void sendPuppeteerClosedCmd(ISerialPort serialPort)
        {
            debug writeln("Sending puppeteerClosedCommand");
            serialPort.write([commandControlByte, 0x99]);
        }
        sendPuppeteerClosedCmd(arduinoSerialPort);

        arduinoSerialPort.close();

        ownerTid.send(CommunicationEndedMessage());
    }
}
