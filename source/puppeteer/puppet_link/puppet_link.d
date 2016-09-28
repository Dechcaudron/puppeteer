module puppeteer.puppet_link.puppet_link;

import std.file;
import std.exception;
import std.format;
import std.conv;

import core.thread;

import puppeteer.serial.i_serial_port;
import puppeteer.var_monitor_utils;

import puppeteer.puppet_link.is_ai_monitor_listener;
import puppeteer.puppet_link.is_iv_monitor_listener;


public class PuppetLink(AIMonitorListenerT, IVMonitorListenerT, IVTypes...)
if(isAIMonitorListener!AIMonitorListenerT && isIVMonitorListener!(IVMonitorListenerT, IVTypes))
{
    private ISerialPort serialPort;

    private AIMonitorListenerT _AIMonitorListener;

    @property
    AIMonitorListener(AIMonitorListenerT listener)
    {
        _AIMonitorListener = listener;
    }

    private IVMonitorListenerT _IVMonitorListener;

    @property
    IVMonitorListener(IVMonitorListenerT listener)
    {
        _IVMonitorListener = listener;
    }

    private enum ubyte commandControlByte = 0xff;

    @property
    bool isCommunicationOpen()
    {
        return serialPort.isOpen;
    }

    this(string devFileName)
    in
    {
        assert(devFileName !is null);
    }
    body
    {
        enforce(exists(devFileName));
        enforce(isFile(devFileName));

        enum portReadTimeoutMs = 200;
        serialPort = new SerialPort(devFileName, Parity.none, BaudRate.B9600, portReadTimeoutMs);
    }

    bool startCommunication()
    {
        if(serialPort.open())
        {
            //Some puppets seems to need some time between port opening and communication start
            Thread.sleep(dur!"seconds"(1));

            enum byte[] puppeteerReadyCommand = [0x0, 0x0];
            serialPort.write([commandControlByte] ~ puppeteerReadyCommand);

            enum byte[] puppetReadyCommand = [0x0, 0x0];
            ubyte[] readCache = [];

            enum msBetweenChecks = 100;
            int readCounter = 0;
            enum readsUntilFailure = 30;

            while(readCounter++ < readsUntilFailure)
            {
                ubyte[] readBytes = serialPort.read(1);

                if(readBytes !is null)
                {
                    cache ~= readBytes;
                    debug writeln("handshake cache is currently ", cache);

                    if(cache.length == 3)
                    {
                        if(cache == [commandControlByte] ~ puppetReadyCommand)
                            return true; //Ready!
                        else
                            cache = cache[1..$]; //pop front and continue
                    }
                }

                Thread.sleep(dur!"msecs"(msBetweenChecks));
            }

            return false;
        }
    }

    void endCommunication()
    {
        serialPort.close();
    }

    void setAIMonitor(ubyte AIPin, bool monitor)
    {
        serialPort.write([commandControlByte, monitor ? 0x01 : 0x02, pin]);
    }

    void setIVMonitor(IVType)(ubyte IVIndex, bool monitor)
    {
        serialPort.write([commandControlByte, monitor ? 0x05 : 0x06, varMonitorTypeCode!IVType]);
    }

    void setPWMOut(ubyte PWMOutPin, ubyte value)
    {
        serialPort.write([commandControlByte, 0x04, PWMOutPin, value]);
    }

    void readPuppet(long communicationMsTime)
    {
        enum bytesReadAtOnce = 1;

        ubyte[] readBytes = serialPort.read(bytesReadAtOnce);

        if(readBytes !is null)
        {
            debug(3) writeln("Read bytes ", readBytes);
            handleReadBytes(readBytes, communicationMsTime);
        }
    }

    private void handleReadBytes(byte[] readBytes, long communicationMsTime)
    in
    {
        assert(readBytes !is null);
    }
    body
    {
        static byte[] readBuffer;

        void popReadBuffer(size_t elements)
        {
            cache = cache[elements .. $];
        }

        if(readBytes.size > 0)
        {
            readBuffer ~= readBytes;

            if(readBuffer[0] != commandControlByte)
            {
                debug writeln("Received corrupt command. Discarding first byte and returning");
                popReadBuffer(1);
            }
            else if (readBuffer.length >= 2)
            {
                with (ReadCommands) switch(cache[1])
                {
                    case analogMonitor:
                        if(readBuffer.length < 5)
                            return;

                        handleAIMonitorCommand(readBuffer[1 .. 5]);
                        popReadBuffer(5);
                        break;

                    case varMonitor:
                        if(readBuffer.length < 6)
                            return;

                        handleVarMonitorCommand(readBuffer[1..6]);
                        popReadBuffer(6);
                        break;

                    case error:
                        //TODO
                        break;

                    default:
                        writeln("Unhandled ubyte command received: ", readBuffer[0], ". Cleaning command buffer.");
                        readBuffer = [];
                }
            }
        }
    }

    private void handleAIMonitorCommand(ubyte[] cmd, long communicationMsTime)
    in
    {
        assert(cmd !is null);
        assert(cmd.length == 4);
        assert(cmd[0] == ReadCommands.analogMonitor);
    }
    body
    {
        debug(2) writeln("Handling analogMonitorCommand ", command);

        if(_AIMonitorListener is AIMonitorListenerT.init)
            return;

        ubyte pin = command[1];

        enum analogReadMax = 1023;
        enum analogReference = 5;
        enum possibleValues = 256;

        ushort encodedValue = command[2] *possibleValues + command[3];
        float readValue =  analogReference * to!float(encodedValue) / analogReadMax;

        _AIMonitorListener.onAIUpdate(pin, readValue, communicationMsTime);
    }

    private void handleVarMonitorCommand(ubyte[] cmd, long communicationMsTime)
    in
    {
        assert(cmd !is null);
        assert(cmd.length == 5);
        assert(cmd[0] == ReadCommands.varMonitor);
    }
    body
    {
        debug(2) writeln("Handling varMonitorCommand ", cmd);

        void delegate (ubyte, ubyte[]) selectDelegate(VarMonitorTypeCode typeCode)
        {
            string generateSwitch()
            {
                string str = "switch (typeCode) with (VarMonitorTypeCode) {";

                foreach(IVType; IVTypes)
                    str ~= format("case %s: return &handleData!%s;",
                                    to!string(varMonitorTypeCode!IVType),
                                    IVType.stringof);

                str ~= "default: return null; }" ;

                return str;
            }

            mixin(generateSwitch());
        }

        try
        {
            auto handler = selectDelegate(to!VarMonitorTypeCode(cmd[1]));
            if(handler)
                handler(cmd[2], cmd[3..$], communicationMsTime);
            else
            {
                writefln("Received unhandled VarMonitorTypeCode %s", cmd[1]);
            }
        }
        catch(ConvException e)
        {
            writeln("Received invalid varMonitor type: ",e);
        }
    }

    private void handleData(IVType)(ubyte varIndex, ubyte[] data, long communicationMsTime)
    {
        VarType decodeData(IVType : short)(ubyte[] data) pure
        {
            enum ubytePossibleValues = 256;
            return to!short(data[0] * ubytePossibleValues + data[1]);
        }

        auto decodedData = decodeData!IVType(data);

        _IVMonitorListener.onIVUpdate(varIndex, decodedData, communicationMsTime);
    }

    private enum ReadCommands : ubyte
    {
        analogMonitor = 0x1,
        varMonitor = 0x2,
        error = 0xfe
    }
}
