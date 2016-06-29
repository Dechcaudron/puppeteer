module puppeteer.puppeteer;

import test.puppeteer.puppeteer_test : test;
mixin test;

public import puppeteer.serial.iserial_port;
public import puppeteer.serial.baud_rate;
public import puppeteer.serial.parity;

import puppeteer.signal_wrapper;
import puppeteer.exception.invalid_adapter_expression_exception;
import puppeteer.exception.invalid_configuration_exception;
import puppeteer.exception.communication_exception;

import std.stdio;
import std.concurrency;
import std.conv;
import std.typecons;
import std.exception;
import std.signals;
import std.meta;
import std.datetime;
import std.exception;

import core.time;
import core.thread;

public alias pinListenerDelegate = void delegate (ubyte, float, long) shared;

private alias hack(alias a) = a;

private enum configAIAdaptersKey = "AIAdapters";
private enum configVarAdaptersKey = "VarAdapters";

class Puppeteer(VarMonitorTypes...)
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
    alias PinSignalWrapper = SignalWrapper!(ubyte, float, long);

    //Manually synchronized between both logical threads
    protected shared PinSignalWrapper[ubyte] pinSignalWrappers;
    protected shared mixin(unrollVariableSignalWrappers!VarMonitorTypes());

    protected shared ValueAdapter!float[ubyte] analogInputValueAdapters;
    protected shared mixin(unrollVariableValueAdapters!VarMonitorTypes());

    enum canMonitor(T) = __traits(compiles, mixin(getVarMonitorSignalWrappersName!T));

    protected shared bool communicationOn;

    string filename;
    immutable Parity parity;
    immutable BaudRate baudRate;

    private Tid workerId;

    public this(string filename, Parity parity = Parity.none, BaudRate baudRate = BaudRate.B9600)
    {
        this.filename = filename;
        this.parity = parity;
        this.baudRate = baudRate;
    }

    public void setAnalogInputValueAdapter(ubyte pin, string adapterExpression)
    {
        setAdapter(analogInputValueAdapters, pin, adapterExpression);
    }

    /// Sets a value adapter for an internal variable of type T
    ///
    /// Params:
    ///
    /// varIndex          =
    /// adapterExpression =
    public void setVarMonitorValueAdapter(T)(ubyte varIndex, string adapterExpression)
    if(canMonitor!T)
    {
        setAdapter(hack!(mixin(getVarMonitorValueAdaptersName!T)), varIndex, adapterExpression);
    }

    private void setAdapter(T)(ref shared ValueAdapter!T[ubyte] adapterDict, ubyte position, string adapterExpression)
    {
        if(adapterExpression)
            adapterDict[position] = shared ValueAdapter!T(adapterExpression);
        else
            adapterDict.remove(position);
    }

    public void addPinListener(ubyte pin, pinListenerDelegate listener)
    in
    {
        assert(listener !is null);
    }
    body
    {
        enforce!CommunicationException(communicationOn);

        auto wrapper = pin in pinSignalWrappers;
        if(!wrapper)
        {
            shared PinSignalWrapper signalWrapper = new PinSignalWrapper;

            pinSignalWrappers[pin] = signalWrapper;

            //No need to synchronize this call since it is the first listener
            signalWrapper.addListener(listener);

            debug writeln("Sending message to dynamically enable monitoring of pin "~to!string(pin));
            workerId.send(PinMonitorMessage(PinMonitorMessage.Action.start, pin));
        }
        else
        {
            shared PinSignalWrapper signalWrapper = *wrapper;

            synchronized(signalWrapper)
            {
                signalWrapper.addListener(listener);
            }
        }
    }


    public void removePinListener(ubyte pin, pinListenerDelegate listener)
    in
    {
        assert(listener !is null);
    }
    body
    {
        enforce!CommunicationException(communicationOn);
        enforce(pin in pinSignalWrappers);

        shared PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

        synchronized(signalWrapper)
            signalWrapper.removeListener(listener);

        if(signalWrapper.listenersNumber == 0)
        {
            pinSignalWrappers.remove(pin);
            workerId.send(PinMonitorMessage(PinMonitorMessage.Action.stop, pin));
        }
    }

    public void addVariableListener(MonitorType)(ubyte varIndex, void delegate(ubyte, MonitorType, long) shared listener)
    if(canMonitor!MonitorType)
    {
        enforce!CommunicationException(communicationOn);
        alias typeSignalWrappers = hack!(mixin(getVarMonitorSignalWrappersName!MonitorType));
        auto wrapper = varIndex in typeSignalWrappers;
        if(wrapper)
        {
            synchronized(*wrapper)
            {
                wrapper.addListener(listener);
            }
        }
        else
        {
            auto signalWrapper = new shared SignalWrapper!(ubyte, MonitorType, long);
            signalWrapper.addListener(listener);
            typeSignalWrappers[varIndex] = signalWrapper;
                workerId.send(VarMonitorMessage(VarMonitorMessage.Action.start, varIndex, getVarMonitorTypeCode!MonitorType));
        }
    }

    public void removeVariableListener(MonitorType)(ubyte varIndex, void delegate(ubyte, MonitorType, long) shared listener)
    if(canMonitor!MonitorType)
    {
        enforce!CommunicationException(communicationOn);
        alias typeSignalWrappers = hack!(mixin(getVarMonitorSignalWrappersName!MonitorType));

        enforce(varIndex in typeSignalWrappers);

        auto signalWrapper = typeSignalWrappers[varIndex];

        synchronized(signalWrapper)
            signalWrapper.removeListener(listener);

        if(signalWrapper.listenersNumber == 0)
        {
            typeSignalWrappers.remove(varIndex);
            workerId.send(VarMonitorMessage(VarMonitorMessage.Action.stop, varIndex, getVarMonitorTypeCode!MonitorType));
        }
    }

    public void setPWM(ubyte pin, ubyte value)
    {
        enforce!CommunicationException(communicationOn);
        workerId.send(SetPWMMessage(pin, value));
    }

    public bool startCommunication()
    {
        enforce!CommunicationException(!communicationOn);

        workerId = spawn(&communicationLoop, filename, baudRate, parity);

        auto msg = receiveOnly!CommunicationEstablishedMessage();
        return msg.success;
    }

    public void endCommunication()
    {
        enforce!CommunicationException(communicationOn);

        workerId.send(EndCommunicationMessage());

        //Remove all listeners
        foreach(pin; pinSignalWrappers.byKey())
        {
            synchronized(pinSignalWrappers[pin])
                pinSignalWrappers.remove(pin);
        }

        //TODO: remove listeners for variables as well

        receiveOnly!CommunicationEndedMessage();
    }

    @property
    bool isCommunicationEstablished()
    {
        return communicationOn;
    }

    public bool saveConfig(string fileName)
    in
    {
        assert(filename !is null);
        assert(filename != "");
    }
    body
    {
        string config = generateConfigString();

        File f = File(fileName, "w");
        scope(exit) f.close();

        if(!f.isOpen)
            return false;

        f.write(config);
        return true;
    }

    public bool loadConfig(string fileName)
    in
    {
        assert(filename !is null);
        assert(filename != "");
    }
    body
    {
        File f = File(fileName, "r");
        scope(exit) f.close();

        if(!f.isOpen)
            return false;

        string content;
        f.readf("%s", &content);

        applyConfig(content);

        return true;
    }

    package void applyConfig(string configStr)
    {
        import std.json;

        JSONValue top = parseJSON(configStr);

        JSONValue aiAdapters = top[configAIAdaptersKey].object;

        foreach(string key, expr; aiAdapters)
        {
            setAnalogInputValueAdapter(to!ubyte(key), expr.str);
        }

        JSONValue varAdapters = top[configVarAdaptersKey].object;

        void setVarMonitorAdapterDynamic(string typeName, ubyte varIndex, string expr)
        {
            string generateSwitch()
            {
                string str = "switch(typeName) {";

                foreach(t; VarMonitorTypes)
                {
                    str ~= "case \"" ~ t.stringof ~ "\":";
                    str ~= "setVarMonitorValueAdapter!" ~ t.stringof ~ "(varIndex, expr);";
                    str ~= "break;";
                }

                str ~= "default: throw new InvalidConfigurationException(\"Type \" ~ typeName ~ \" is not supported by this Puppeteer\");";
                str ~= "}";

                return str;
            }

            mixin(generateSwitch());
        }

        foreach(string typeName, innerJson; varAdapters)
        {
            foreach(string varIndex, expr; innerJson)
            {
                setVarMonitorAdapterDynamic(typeName, to!ubyte(varIndex), expr.str);
            }
        }
    }

    private string generateConfigString()
    {
        import std.json;

        enum emptyJson = string[string].init;

        JSONValue config = JSONValue(emptyJson);
        JSONValue AIAdapters = JSONValue(emptyJson);

        foreach(pin, adapter; analogInputValueAdapters)
        {
            AIAdapters.object[to!string(pin)] = JSONValue(adapter.expression);
        }

        config.object[configAIAdaptersKey] = AIAdapters;

        JSONValue varAdapters = JSONValue(emptyJson);

        foreach(member; __traits(allMembers, VarMonitorTypeCode))
        {
            static if(canMonitor!(getVarMonitorType!(hack!(mixin("VarMonitorTypeCode." ~ member)))))
            {
                alias varMonitorAdapters = hack!(mixin(getVarMonitorValueAdaptersName!(getVarMonitorType!(hack!(mixin("VarMonitorTypeCode." ~ member))))));

                if(varMonitorAdapters.length > 0)
                {
                    string typeName = member[0 .. $-2];

                    JSONValue typeMonitorAdaptersJSON = JSONValue(emptyJson);

                    foreach(varIndex, adapter; varMonitorAdapters)
                    {
                        typeMonitorAdaptersJSON.object[to!string(varIndex)] = JSONValue(adapter.expression);
                    }

                    varAdapters.object[typeName] = typeMonitorAdaptersJSON;
                }
            }
        }

        config.object[configVarAdaptersKey] = varAdapters;

        return config.toPrettyString();
    }


    private void communicationLoop(string fileName, immutable BaudRate baudRate, immutable Parity parity) shared
    {
        enum receiveTimeoutMs = 10;
        enum bytesReadAtOnce = 1;

        enum ubyte commandControlByte = 0xff;

        bool shouldContinue = true;

        ISerialPort arduinoSerialPort;

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
                debug(2) writeln("Handling analogMonitorCommand ", command);

                ubyte pin = command[1];

                auto signalWrapper = pin in pinSignalWrappers;
                if(signalWrapper)
                {
                    enum arduinoAnalogReadMax = 1023;
                    enum arduinoAnalogReference = 5;
                    enum ubytePossibleValues = 256;

                    ushort readValue = command[2] * ubytePossibleValues + command[3];
                    float realValue =  arduinoAnalogReference * to!float(readValue) / arduinoAnalogReadMax;

                    float adaptedValue = realValue;
                    auto adapter = pin in analogInputValueAdapters;
                    if(adapter)
                    {
                        adaptedValue = adapter.opCall(realValue);
                    }

                    synchronized(*signalWrapper)
                    {
                        signalWrapper.emit(pin, adaptedValue, timer.peek().msecs);
                    }

                }
                else
                    debug(2) writeln("No listeners registered for pin ",pin);
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
                debug(2) writeln("Handling varMonitorCommand ", command);

                void handleData(VarType)(ubyte varIndex, ubyte[] data)
                if(canMonitor!VarType)
                {
                    void emitData(VarType)(ubyte varIndex, VarType data)
                    {
                        alias varTypeSignalWrappers = hack!(mixin(getVarMonitorSignalWrappersName!VarType));
                        auto wrapper = varIndex in varTypeSignalWrappers;

                        if(wrapper)
                        {
                            auto signalWrapper = *wrapper;

                            synchronized(signalWrapper)
                            {
                                signalWrapper.emit(varIndex, data, timer.peek().msecs);
                            }
                        }
                        else
                            debug(2) writeln("SignalWrapper for type ", VarType.stringof, "and varIndex ", varIndex, "was no longer in its SignalWrapper assoc array. Skipping signal emission.");
                    }

                    VarType decodeData(VarType : short)(ubyte[] data) pure
                    {
                        enum ubytePossibleValues = 256;
                        return to!short(data[0] * ubytePossibleValues + data[1]);
                    }

                    VarType adaptData(VarType)(VarType data)
                    {
                        alias typeAdapters = hack!(mixin(getVarMonitorValueAdaptersName!VarType));

                        auto adapter = varIndex in typeAdapters;

                        if(adapter)
                            return adapter.opCall(data);
                        else
                            return data;
                    }

                    emitData(varIndex, adaptData(decodeData!VarType(data)));
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

        //Arduino seems to need some time between port opening and communication start
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

        communicationOn = true;
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

        communicationOn = false;
        arduinoSerialPort.close();

        ownerTid.send(CommunicationEndedMessage());
    }

    private struct CommunicationEstablishedMessage
    {
        bool success;

        this(bool success)
        {
            this.success = success;
        }
    }

    private struct CommunicationEndedMessage
    {

    }

    private struct EndCommunicationMessage
    {

    }

    private struct PinMonitorMessage
    {
        enum Action
        {
            start,
            stop
        }

        private Action action;
        private ubyte pin;

        this(Action action, ubyte pin)
        {
            this.action = action;
            this.pin = pin;
        }
    }

    private struct VarMonitorMessage
    {
        enum Action
        {
            start,
            stop
        }

        private Action action;
        private ubyte varIndex;
        private VarMonitorTypeCode varTypeCode;

        this(Action action, ubyte varIndex, VarMonitorTypeCode varTypeCode)
        {
            this.action = action;
            this.varIndex = varIndex;
            this.varTypeCode = varTypeCode;
        }
    }

    private struct SetPWMMessage
    {
        ubyte pin;
        ubyte value;

        this(ubyte pin, ubyte value)
        {
            this.pin = pin;
            this.value = value;
        }
    }


}

private shared struct ValueAdapter(T)
{
    import arith_eval.evaluable;

    private Evaluable!(T, "x") evaluable;
    private string expression;

    this(string xBasedValueAdapterExpr)
    {
        try
        {
            evaluable = Evaluable!(T,"x")(xBasedValueAdapterExpr);
        }
        catch(InvalidExpressionException e)
        {
            throw new InvalidAdapterExpressionException("Can't create ValueAdapter with expression " ~ xBasedValueAdapterExpr);
        }

        expression = xBasedValueAdapterExpr;
    }

    T opCall(T value) const
    {
        return evaluable(value);
    }
}
unittest
{
    auto a = shared ValueAdapter!float("x / 3");
    assert(a(3) == 1.0f);
    assert(a(1) == 1.0f / 3);

    auto b = shared ValueAdapter!float("x**2 + 1");
    assert(b(3) == 10.0f);
    assert(b(5) == 26.0f);

    b = shared ValueAdapter!float("x");
    assert(b(1) == 1f);

    auto c = shared ValueAdapter!int("x * 3");
    assert(c(3) == 9);

}

private enum VarMonitorTypeCode : byte
{
    short_t = 0x0,
}

private enum isVarMonitorTypeSupported(VarType) = __traits(compiles, getVarMonitorTypeCode!VarType);
unittest
{
    assert(isVarMonitorTypeSupported!short);
    assert(!isVarMonitorTypeSupported!float);
    assert(!isVarMonitorTypeSupported!void);
}


private alias getVarMonitorTypeCode(VarType) = hack!(mixin(VarMonitorTypeCode.stringof ~ "." ~ VarType.stringof ~ "_t"));
unittest
{
    assert(getVarMonitorTypeCode!short == VarMonitorTypeCode.short_t);
}

private alias h(T) = T;
private alias getVarMonitorType(VarMonitorTypeCode typeCode) = h!(mixin("h!(" ~ to!string(typeCode)[0..$-2] ~ ")"));
unittest
{
    with(VarMonitorTypeCode)
    {
        assert(is(getVarMonitorType!short_t == short));
    }
}

private pure string unrollVariableSignalWrappers(VarTypes...)()
{
    string unroll = "";

    foreach(varType; VarTypes)
    {
        unroll ~= getVarMonitorSignalWrappersType!varType ~ " " ~ getVarMonitorSignalWrappersName!varType ~ ";\n";
    }

    return unroll;
}


private enum getVarMonitorSignalWrappersType(VarType) = "SignalWrapper!(ubyte, " ~ VarType.stringof ~ ", long)[ubyte]";
unittest
{
    assert(getVarMonitorSignalWrappersType!int == "SignalWrapper!(ubyte, int, long)[ubyte]");
    assert(getVarMonitorSignalWrappersType!float == "SignalWrapper!(ubyte, float, long)[ubyte]");
    assert(getVarMonitorSignalWrappersType!byte == "SignalWrapper!(ubyte, byte, long)[ubyte]");
}


private enum getVarMonitorSignalWrappersName(VarType) = VarType.stringof ~ "SignalWrappers";
unittest
{
    assert(getVarMonitorSignalWrappersName!int == "intSignalWrappers");
}


private pure string unrollVariableValueAdapters(VarTypes...)()
{
    string unroll = "";

    foreach(varType; VarTypes)
    {
        unroll ~= getVarMonitorValueAdaptersType!varType ~ " " ~ getVarMonitorValueAdaptersName!varType ~ ";\n";
    }

    return unroll;
}

private enum getVarMonitorValueAdaptersType(VarType) = "ValueAdapter!(" ~ VarType.stringof ~ ")[ubyte]";
private enum getVarMonitorValueAdaptersName(VarType) = VarType.stringof ~ "ValueAdapters";