module puppeteer.puppeteer;

import test.puppeteer.puppeteer_test : test;
mixin test;

public import puppeteer.serial.iserial_port;
public import puppeteer.serial.baud_rate;
public import puppeteer.serial.parity;

import puppeteer.signal_wrapper;
import puppeteer.exception.invalid_adapter_expression_exception;
import puppeteer.communicator;
import puppeteer.var_monitor_utils;
import puppeteer.puppeteer_config;
import puppeteer.logging.ipuppeteer_logger;

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
    protected shared PinSignalWrapper[ubyte] pinSignalWrappers;
    protected shared mixin(unrollVariableSignalWrappers!VarMonitorTypes());

    protected Communicator!VarMonitorTypes communicator;

    protected PuppeteerConfig!VarMonitorTypes config;

    @property
    shared(PuppeteerConfig!VarMonitorTypes) configuration()
    {
        return config;
    }

    enum canMonitor(T) = __traits(compiles, mixin(getVarMonitorSignalWrappersName!T));

    @property
    bool isCommunicationEstablished()
    {
        return communicator.isCommunicationEstablished;
    }

    this(shared Communicator!VarMonitorTypes communicator)
    {
        this.communicator = communicator;
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
            {
                wrapper.addListener(listener);
            }
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
        setPWM(pin, getPWMFromAverage!pwmHigh(averageValue));
    }

    private ubyte getPWMFromAverage(float pwmHigh)(float averageValue)
    {
        import std.math;
        return to!ubyte(round(averageValue / pwmHigh * ubyte.max));
    }

    public bool startCommunication(string devFilename, BaudRate baudRate, Parity parity, string logFilename)
    {
        communicator.startCommunication(devFilename, baudRate, parity, logFilename);
    }

    public void endCommunication()
    {
        communicator.endCommunication();

        //Remove all listeners
        foreach(pin; pinSignalWrappers.byKey())
        {
            synchronized(pinSignalWrappers[pin])
                pinSignalWrappers.remove(pin);
        }

        //TODO: remove listeners for variables as well
    }

    package void emitAIRead(byte pin, float readValue, long readMilliseconds)
    {
        float adaptedValue;

        auto adapter = pin in AIValueAdapters;
        if(adapter)
        {
            adaptedValue = adapter(realValue);
        }
        else
        {
            adaptedValue = readValue;
        }

        auto signalWrapper = pin in pinSignalWrappers;
        if(signalWrapper)
        {
            synchronized(*signalWrapper)
            {
                signalWrapper.emit(pin, readValue, adaptedValue, timer.peek().msecs);
            }
        }
        else
            debug(2) writeln("No listeners registered for pin ",pin);

        logger.logSensor(timer.peek().msecs, getAISensorName(pin), to!string(realValue), to!string(adaptedValue));
    }

    package void emitVarRead(VarMonitorType)(byte varIndex, VarMonitorType readValue, long readMilliseconds)
    if(canMonitor!VarMonitorType)
    {
        VarMonitorType adaptedValue;

        // Adapt value
        {
            alias typeAdapters = Alias!(mixin(getVarMonitorValueAdaptersName!VarType));

            auto adapter = varIndex in typeAdapters;
            if(adapter)
                adaptedValue = adapter(readValue);
            else
                adaptedValue = readValue;
        }

        alias varTypeSignalWrappers = Alias!(mixin(getVarMonitorSignalWrappersName!VarMonitorType));

        auto wrapper = varIndex in varTypeSignalWrappers;
        if(wrapper)
        {
            synchronized(*signalWrapper)
            {
                signalWrapper.emit(varIndex, readValue, adaptedData, readMilliseconds);
            }
        }
        else
            debug(2) writeln("SignalWrapper for type ", VarType.stringof, "and varIndex ", varIndex, "was no longer in its SignalWrapper assoc array. Skipping signal emission.");

        logger.logSensor(timer.peek().msecs, this.getVarMonitorSensorName!VarType(varIndex), to!string(receivedData), to!string(adaptedData));
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
