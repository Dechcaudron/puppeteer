module puppeteer.puppet_link.puppet_link;

import std.file;
import std.exception;

import core.thread;

import puppeteer.serial.i_serial_port;
import puppeteer.var_monitor_utils;

public class PuppetLink(AIMonitorListenerT, IVMonitorListenerT, IVTypes...)
{
    private ISerialPort serialPort;

    private byte CommandControlByte = 0xff;

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

        enum int PortReadTimeoutMs = 200;
        serialPort = new SerialPort(devFileName, Parity.none, BaudRate.B9600, PortReadTimeoutMs);
    }

    bool startCommunication()
    {
        if(serialPort.open())
        {
            //Some puppets seems to need some time between port opening and communication start
            Thread.sleep(dur!"seconds"(1));

            enum byte[] PuppeteerReadyCommand = [0x0, 0x0];
            serialPort.write([CommandControlByte] ~ PuppeteerReadyCommand);

            enum byte[] PuppetReadyCommand = [0x0, 0x0];
            ubyte[] readCache = [];

            enum msBetweenChecks = 100;
            int readCounter = 0;
            enum ReadsUntilFailure = 30;

            while(readCounter++ < ReadsUntilFailure)
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
        serialPort.write([CommandControlByte, monitor ? 0x01 : 0x02, pin]);
    }

    void setIVMonitor(ubyte IVIndex, VarMonitorTypeCode typeCode, bool monitor)
    {
        serialPort.write([CommandControlByte, monitor ? 0x05 : 0x06, typeCode]);
    }

    void setPWMOut(ubyte PWMOutPin, ubyte value)
    {
        serialPort.write([CommandControlByte, 0x04, PWMOutPin, value]);
    }

    void readPuppet()
    {
        enum BytesReadAtOnce = 1;

        ubyte[] readBytes = serialPort.read(BytesReadAtOnce);

        if(readBytes !is null)
        {
            debug(3) writeln("Read bytes ", readBytes);
            handleReadBytes(readBytes);
        }
    }

    private void handleReadBytes(byte[] readBytes)
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

            if(readBuffer[0] != CommandControlByte)
            {
                debug writeln("Received corrupt command. Discarding first byte and returning");
                popReadBuffer(1);
            }
            else if (readBuffer.length >= 2)
            {
                with (ReadCommands) witch(cache[1])
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

    private void handleAIMonitorCommand(ubyte[] cmd)
    in
    {
        assert(cmd !is null);
        assert(cmd.length == 4);
        assert(cmd[0] == ReadCommands.analogMonitor);
    }
    body
    {
        debug(2) writeln("Handling analogMonitorCommand ", command);

        ubyte pin = command[1];

        enum AnalogReadMax = 1023;
        enum AnalogReference = 5;
        enum PossibleValues = 256;

        ushort encodedValue = command[2] * PossibleValues + command[3];
        float readValue =  AnalogReference * to!float(encodedValue) / AnalogReadMax;
    }

    private void handleVarMonitorCommand(ubyte[] cmd)
    {

    }

    private enum ReadCommands : ubyte
    {
        analogMonitor = 0x1,
        varMonitor = 0x2,
        error = 0xfe
    }
}
