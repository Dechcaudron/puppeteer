module puppeteer.configuration.configuration;

import test.puppeteer.configuration.configuration_test : test;
mixin test;

import puppeteer.var_monitor_utils;
import puppeteer.value_adapter.value_adapter;

import puppeteer.configuration.iconfiguration;

import puppeteer.configuration.invalid_configuration_exception;

import std.meta;
import std.conv;
import std.stdio;

private enum configAIAdaptersKey = "AI_ADAPTERS";
private enum configVarAdaptersKey = "VAR_ADAPTERS";

shared class Configuration(VarMonitorTypes...) : IConfiguration!VarMonitorTypes
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
    protected ValueAdapter!float[ubyte] AIValueAdapters;
    protected mixin(unrollVariableValueAdapters!VarMonitorTypes());

    protected string[ubyte] AISensorNames;
    protected mixin(unrollVarMonitorSensorNames!VarMonitorTypes());

    //pragma(msg, unrollHelperMethods!VarMonitorTypes());
    mixin(unrollHelperMethods!VarMonitorTypes());

    public void setAIValueAdapterExpression(ubyte pin, string adapterExpression)
    {
        setAdapterExpression(AIValueAdapters, pin, adapterExpression);
    }

    public string getAIValueAdapterExpression(ubyte pin) const
    {
        auto adapter = pin in AIValueAdapters;

        return adapter ? adapter.expression : "";
    }

    public float adaptAIValue(ubyte pin, float value) const
    {
        auto adapter = pin in AIValueAdapters;

        return adapter ? adapter.opCall(value) : value;
    }

    public void setVarMonitorValueAdapterExpression(VarType)(ubyte varIndex, string adapterExpression)
    {
        alias adapterDict = Alias!(mixin(getVarMonitorValueAdaptersName!VarType));
        setAdapterExpression(adapterDict, varIndex, adapterExpression);
    }

    public string getVarMonitorValueAdapterExpression(VarType)(ubyte varIndex) const
    {
        alias adapterDict = Alias!(mixin(getVarMonitorValueAdaptersName!VarType));

        auto adapter = varIndex in adapterDict;

        return adapter ? adapter.expression : "";
    }

    public VarType adaptVarMonitorValue(VarType)(ubyte varIndex, VarType value) const
    {
        alias adapterDict = Alias!(mixin(getVarMonitorValueAdaptersName!VarType));

        auto adapter = varIndex in adapterDict;

        return adapter ? adapter.opCall(value) : value;
    }

    private void setAdapterExpression(T)(ref shared ValueAdapter!T[ubyte] adapterDict, ubyte position, string adapterExpression)
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
    {
        setSensorName(mixin(getVarMonitorSensorNames!MonitorType), position, name);
    }

    public string getVarMonitorSensorName(MonitorType)(ubyte position) const
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

    public void load(File configFile)
    {
        debug writeln("Trying to load configuration from file ", configFile.name != "" ? configFile.name : "with no name");

        string content;
        configFile.readf("%s", &content);

        load(content);
        debug writeln("Success!");
    }

    public void load(string configStr)
    {
        void setVarMonitorAdapterDynamic(string typeName, ubyte varIndex, string expr)
        {
            string generateSwitch()
            {
                string str = "switch(typeName) {";

                foreach(t; VarMonitorTypes)
                {
                    str ~= "case \"" ~ t.stringof ~ "\":";
                    str ~= "setVarMonitorValueAdapterExpression!" ~ t.stringof ~ "(varIndex, expr);";
                    str ~= "break;";
                }

                str ~= "default: throw new InvalidConfigurationException(\"Type \" ~ typeName ~ \" is not supported by this Puppeteer\");";
                str ~= "}";

                return str;
            }

            mixin(generateSwitch());
        }

        import std.json;

        try
        {
            JSONValue top = parseJSON(configStr);

            JSONValue aiAdapters = top[configAIAdaptersKey].object;

            foreach(string key, expr; aiAdapters)
            {
                setAIValueAdapterExpression(to!ubyte(key), expr.str);
            }

            JSONValue varAdapters = top[configVarAdaptersKey].object;

            foreach(string typeName, innerJson; varAdapters)
            {
                foreach(string varIndex, expr; innerJson)
                {
                    setVarMonitorAdapterDynamic(typeName, to!ubyte(varIndex), expr.str);
                }
            }
        }
        catch(JSONException e)
        {
            debug writeln(e);
            throw new InvalidConfigurationException("Invalid configuration string: " ~ configStr);
        }
    }

    public void save(File sinkFile, bool flush = true) const
    {
        debug writeln("Trying to save configuration in file ", sinkFile.name != "" ? sinkFile.name : "with no name");

        sinkFile.write(save());
        if(flush)
            sinkFile.flush();

        debug writeln("Sucess!");
    }

    public string save() const
    {
        import std.json;

        enum emptyJson = string[string].init;

        JSONValue config = JSONValue(emptyJson);
        JSONValue AIAdapters = JSONValue(emptyJson);

        foreach(pin, adapter; AIValueAdapters)
        {
            AIAdapters.object[to!string(pin)] = JSONValue(adapter.expression);
        }

        config.object[configAIAdaptersKey] = AIAdapters;

        JSONValue varAdapters = JSONValue(emptyJson);

        foreach(T; VarMonitorTypes)
        {
            alias varMonitorAdapters = Alias!(mixin(getVarMonitorValueAdaptersName!(getVarMonitorType!(Alias!(mixin("VarMonitorTypeCode._" ~ T.stringof))))));

            if(varMonitorAdapters.length > 0)
            {
                string typeName = T.stringof;

                JSONValue typeMonitorAdaptersJSON = JSONValue(emptyJson);

                foreach(varIndex, adapter; varMonitorAdapters)
                {
                    typeMonitorAdaptersJSON.object[to!string(varIndex)] = JSONValue(adapter.expression);
                }

                varAdapters.object[typeName] = typeMonitorAdaptersJSON;
            }
        }

        config.object[configVarAdaptersKey] = varAdapters;

        return config.toPrettyString();
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
