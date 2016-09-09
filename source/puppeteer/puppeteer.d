module puppeteer.puppeteer;

import test.puppeteer.puppeteer_test : test;
mixin test;

public import puppeteer.serial.iserial_port;
public import puppeteer.serial.baud_rate;
public import puppeteer.serial.parity;

import puppeteer.signal_wrapper;
import puppeteer.var_monitor_utils;

import puppeteer.logging.ipuppeteer_logger;

import puppeteer.value_adapter.invalid_adapter_expression_exception;

import puppeteer.communication.icommunicator;

import puppeteer.configuration.iconfiguration;

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

public alias pinListenerDelegate = void delegate (ubyte, float, float, long) shared;
private alias varMonitorDelegateType(VarType) = AliasSeq!(ubyte, VarType, VarType, long);

// Currently disabled due to not being able to be expanded into a function argument and then used from another type
// Manually writing the delegate type as the function argument will have to do by now
@disable
public alias varMonitorDelegate(VarType) = void delegate (varMonitorDelegateType!VarType) shared;

shared class Puppeteer(VarMonitorTypes...)
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
    alias PinSignalWrapper = SignalWrapper!(ubyte, float, float, long);

    //Manually synchronized between both logical threads
    protected PinSignalWrapper[ubyte] pinSignalWrappers;
    protected mixin(unrollVariableSignalWrappers!VarMonitorTypes());

    protected ICommunicator!VarMonitorTypes communicator;

    protected IConfiguration!VarMonitorTypes config;

    protected IPuppeteerLogger logger;

    @property
    shared(IConfiguration!VarMonitorTypes) configuration()
    {
        return config;
    }

    enum canMonitor(T) = __traits(compiles, mixin(getVarMonitorSignalWrappersName!T));

    @property
    bool isCommunicationEstablished()
    {
        return communicator.isCommunicationOngoing;
    }

    this(scope shared ICommunicator!VarMonitorTypes communicator, shared IConfiguration!VarMonitorTypes configuration, scope shared IPuppeteerLogger logger)
    {
        this.communicator = communicator;
        this.config = configuration;
        this.logger = logger;
    }

    ~this()
    {
        destroy(logger);
    }

    public void addPinListener(ubyte pin, pinListenerDelegate listener)
    in
    {
        assert(listener !is null);
    }
    body
    {
        auto wrapper = pin in pinSignalWrappers;
        if(!wrapper)
        {
            shared PinSignalWrapper signalWrapper = new PinSignalWrapper;

            pinSignalWrappers[pin] = signalWrapper;

            //No need to synchronize this call since it is the first listener
            signalWrapper.addListener(listener);

            communicator.changeAIMonitorStatus(pin, true);
        }
        else
        {
            shared PinSignalWrapper signalWrapper = *wrapper;

            synchronized(signalWrapper)
                signalWrapper.addListener(listener);
        }
    }

    public void removePinListener(ubyte pin, pinListenerDelegate listener)
    in
    {
        assert(listener !is null);
    }
    body
    {
        enforce(pin in pinSignalWrappers);

        shared PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

        synchronized(signalWrapper)
            signalWrapper.removeListener(listener);

        if(signalWrapper.listenersNumber == 0)
        {
            pinSignalWrappers.remove(pin);
            communicator.changeAIMonitorStatus(pin, false);
        }
    }

    public void addVariableListener(VarType)(ubyte varIndex, void delegate(ubyte, VarType, VarType, long) shared listener)
    if(canMonitor!VarType)
    in
    {
        assert(listener !is null);
    }
    body
    {
        alias typeSignalWrappers = Alias!(mixin(getVarMonitorSignalWrappersName!VarType));
        auto wrapper = varIndex in typeSignalWrappers;

        if(wrapper)
        {
            synchronized(*wrapper)
                wrapper.addListener(listener);
        }
        else
        {
            auto signalWrapper = new shared SignalWrapper!(varMonitorDelegateType!VarType);
            signalWrapper.addListener(listener);
            typeSignalWrappers[varIndex] = signalWrapper;

            communicator.changeVarMonitorStatus!VarType(varIndex, true);
        }
    }

    public void removeVariableListener(VarType)(ubyte varIndex, void delegate(ubyte, VarType, VarType, long) shared listener)
    if(canMonitor!VarType)
    in
    {
        assert(listener !is null);
    }
    body
    {
        alias typeSignalWrappers = Alias!(mixin(getVarMonitorSignalWrappersName!VarType));

        enforce(varIndex in typeSignalWrappers);

        auto signalWrapper = typeSignalWrappers[varIndex];

        synchronized(signalWrapper)
            signalWrapper.removeListener(listener);

        if(signalWrapper.listenersNumber == 0)
        {
            typeSignalWrappers.remove(varIndex);
            communicator.changeVarMonitorStatus!VarType(varIndex, false);
        }
    }

    public void setPWM(ubyte pin, ubyte value)
    {
        communicator.setPWMValue(pin, value);
    }

    public void setPWMAverage(ubyte pin, float averageValue)
    {
        enum pwmHigh = 5;
        float adaptedAvg = configuration.adaptPWMOutAvgValue(pin, averageValue);
        setPWM(pin, getPWMFromAverage!pwmHigh(adaptedAvg));
    }

    private ubyte getPWMFromAverage(float pwmHigh)(float averageValue)
    {
        import std.math;
        return to!ubyte(round(averageValue / pwmHigh * ubyte.max));
    }

    public bool startCommunication(string devFilename, BaudRate baudRate, Parity parity, string logFilename)
    {
        return communicator.startCommunication(this, devFilename, baudRate, parity, logFilename);
    }

    public void endCommunication()
    {
        communicator.endCommunication();

        //Remove all listeners
        foreach(pin; pinSignalWrappers.byKey())
            synchronized(pinSignalWrappers[pin])
                pinSignalWrappers.remove(pin);


        //TODO: remove listeners for variables as well
    }

    package void emitAIRead(byte pin, float readValue, long readMilliseconds)
    {
        auto signalWrapper = pin in pinSignalWrappers;
        if(signalWrapper)
        {
            synchronized(*signalWrapper)
                signalWrapper.emit(pin, readValue, config.adaptAIValue(pin, readValue), readMilliseconds);
        }
        else
        {
            debug(2) writeln("No listeners registered for pin ",pin);
        }

        logger.logSensor(readMilliseconds, config.getAISensorName(pin), to!string(readValue), to!string(config.adaptAIValue(pin, readValue)));
    }

    package void emitVarRead(VarType)(byte varIndex, VarType readValue, long readMilliseconds)
    if(canMonitor!VarType)
    {
        VarType adaptedValue = config.adaptVarMonitorValue(varIndex, readValue);

        alias varTypeSignalWrappers = Alias!(mixin(getVarMonitorSignalWrappersName!VarType));

        auto wrapper = varIndex in varTypeSignalWrappers;
        if(wrapper)
        {
            synchronized(*wrapper)
                wrapper.emit(varIndex, readValue, adaptedValue, readMilliseconds);
        }
        else
        {
            debug(2) writeln("SignalWrapper for type ", VarType.stringof, "and varIndex ", varIndex, "was no longer in its SignalWrapper assoc array. Skipping signal emission.");
        }

        logger.logSensor(readMilliseconds, config.getVarMonitorSensorName!VarType(varIndex), to!string(readValue), to!string(adaptedValue));
    }
}

private pure string unrollVariableSignalWrappers(VarTypes...)()
{
    string unroll = "";

    foreach(varType; VarTypes)
        unroll ~= getVarMonitorSignalWrappersType!varType ~ " " ~ getVarMonitorSignalWrappersName!varType ~ ";\n";

    return unroll;
}


private enum getVarMonitorSignalWrappersType(VarType) = "SignalWrapper!(ubyte, " ~ VarType.stringof ~ ", " ~ VarType.stringof ~ ", long)[ubyte]";
unittest
{
    assert(getVarMonitorSignalWrappersType!int == "SignalWrapper!(ubyte, int, int, long)[ubyte]");
    assert(getVarMonitorSignalWrappersType!float == "SignalWrapper!(ubyte, float, float, long)[ubyte]");
    assert(getVarMonitorSignalWrappersType!byte == "SignalWrapper!(ubyte, byte, byte, long)[ubyte]");
}


private enum getVarMonitorSignalWrappersName(VarType) = VarType.stringof ~ "SignalWrappers";
unittest
{
    assert(getVarMonitorSignalWrappersName!int == "intSignalWrappers");
}
