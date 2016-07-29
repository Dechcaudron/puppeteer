module puppeteer.puppeteer_config;

import puppeteer.var_monitor_utils;
import puppeteer.value_adapter;

import std.meta : allSatisfy;

class PuppeteerConfig(VarMonitorTypes...) shared
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
    protected ValueAdapter!float[ubyte] AIValueAdapters;
    protected mixin(unrollVariableValueAdapters!VarMonitorTypes());

    protected string[ubyte] AISensorNames;
    protected mixin(unrollVarMonitorSensorNames!VarMonitorTypes());

    public void setAIValueAdapter(ubyte pin, string adapterExpression)
    {
        setAdapter(AIValueAdapters, pin, adapterExpression);
    }

    public string getAIValueAdapter(ubyte pin)
    {
        if(pin in AIValueAdapters)
        {
            return AIValueAdapters[pin].expression;
        }
        else
        {
            return "";
        }
    }

    public void setVarMonitorValueAdapter(T)(ubyte varIndex, string adapterExpression)
    if(canMonitor!T)
    {
        alias adapterDict = Alias!(mixin(getVarMonitorValueAdaptersName!T));
        setAdapter(adapterDict, varIndex, adapterExpression);
    }

    public string getVarMonitorValueAdapter(VarType)(ubyte varIndex)
    if(canMonitor!VarType)
    {
        alias adapterDict = Alias!(mixin(getVarMonitorValueAdaptersName!VarType));

        if(varIndex in adapterDict)
        {
            return adapterDict[varIndex].expression;
        }
        else
            return "";
    }

    private void setAdapter(T)(ref shared ValueAdapter!T[ubyte] adapterDict, ubyte position, string adapterExpression)
    {
        if(adapterExpression)
            adapterDict[position] = shared ValueAdapter!T(adapterExpression);
        else
            adapterDict.remove(position);
    }

    public void setAISensorName(ubyte pin, string name)
    {
        setSensorName(AISensorNames, pin, name);
    }

    public string getAISensorName(ubyte pin) const
    {
        return getSensorName(AISensorNames, pin, "AI(" ~ to!string(pin) ~ ")");
    }

    public void setVarMonitorSensorName(MonitorType)(ubyte position, string name)
    if(canMonitor!MonitorType)
    {
        setSensorName(mixin(getVarMonitorSensorNames!MonitorType), position, name);
    }

    public string getVarMonitorSensorName(MonitorType)(ubyte position) const
    if(canMonitor!MonitorType)
    {
        return getSensorName(mixin(getVarMonitorSensorNames!MonitorType), position, varMonitorSensorDefaultName!MonitorType ~ "(" ~ to!string(position) ~ ")");
    }

    private void setSensorName(ref shared string[ubyte] namesDict, ubyte position, string name)
    {
        if(name)
            namesDict[position] = name;
        else
            namesDict.remove(position);
    }

    private string getSensorName(ref in shared string[ubyte] namesDict, ubyte position, string defaultName) const
    {
        if(position in namesDict)
            return namesDict[position];
        else
            return defaultName;
    }
}

//Clean this
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

private enum getVarMonitorSensorNames(VarType) = VarType.stringof ~ "SensorNames";

private pure string unrollVarMonitorSensorNames(VarTypes...)()
{
    string unroll = "";

    foreach(varType; VarTypes)
    {
        unroll ~= "string[ubyte] " ~ getVarMonitorSensorNames!varType ~ ";\n";
    }

    return unroll;
}
