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
import std.json;

private enum configAIAdaptersKey = "AI_ADAPTERS";
private enum configPWMOutAvgAdaptersKey = "PWM_OUT_AVG_ADAPTERS";
private enum configVarAdaptersKey = "VAR_ADAPTERS";

private enum configAISensorNamesKey = "AI_SENSOR_NAMES";
private enum configVarSensorNamesKey = "VAR_SENSOR_NAMES";

shared class Configuration(VarMonitorTypes...) : IConfiguration!VarMonitorTypes
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
    protected ValueAdapter!float[ubyte] AIValueAdapters;
    protected ValueAdapter!float[ubyte] PWMOutAvgValueAdapters;
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

        return adapter ? adapter.expression : "x";
    }

    public float adaptAIValue(ubyte pin, float value) const
    {
        auto adapter = pin in AIValueAdapters;

        return adapter ? adapter.opCall(value) : value;
    }

    public void setPWMOutAvgAdapterExpression(ubyte pin, string adapterExpression)
    {
        setAdapterExpression(PWMOutAvgValueAdapters, pin, adapterExpression);
    }

    public string getPWMOutAvgAdapterExpression(ubyte pin) const
    {
        auto adapter = pin in PWMOutAvgValueAdapters;

        return adapter ? adapter.expression : "x";
    }

    public float adaptPWMOutAvgValue(ubyte pin, float value) const
    {
        auto adapter = pin in PWMOutAvgValueAdapters;

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

        return adapter ? adapter.expression : "x";
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
        return getSensorName(AISensorNames, pin, "AI_" ~ to!string(pin));
    }

    public void setVarMonitorSensorName(MonitorType)(ubyte position, string name)
    {
        setSensorName(varMonitorSensorNames!MonitorType, position, name);
    }

    public string getVarMonitorSensorName(MonitorType)(ubyte position) const
    {
        return getSensorName(varMonitorSensorNames!MonitorType, position, varMonitorDefaultSensorName!MonitorType ~ "(" ~ to!string(position) ~ ")");
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
        string generateSwitch(string method, string arguments)
        {
            string str = "switch(typeName) {";

            foreach(t; VarMonitorTypes)
            {
                str ~= "case \"" ~ t.stringof ~ "\":";
                str ~=  method ~ "!" ~ t.stringof ~ arguments ~ ";";
                str ~= "break;";
            }

            str ~= "default: throw new InvalidConfigurationException(\"Type \" ~ typeName ~ \" is not supported by this Puppeteer\");";
            str ~= "}";

            return str;
        }

        void setVarMonitorAdapterDynamic(string typeName, ubyte varIndex, string expr)
        {
            mixin(generateSwitch("setVarMonitorValueAdapterExpression", "(varIndex, expr)"));
        }

        void setVarMonitorSensorNameDynamic(string typeName, ubyte varIndex, string name)
        {
            mixin(generateSwitch("setVarMonitorSensorName", "(varIndex, name)"));
        }

        try
        {
            foreach(string key, inner; parseJSON(configStr).object)
            {
                switch(key)
                {
                    case configAIAdaptersKey:
                        foreach(string pin, expr; inner.object)
                            setAIValueAdapterExpression(to!ubyte(pin), expr.str);
                        break;

                    case configPWMOutAvgAdaptersKey:
                        foreach(string pin, expr; inner.object)
                            setPWMOutAvgAdapterExpression(to!ubyte(pin), expr.str);
                        break;

                    case configVarAdaptersKey:
                        foreach(string typeName, innerJson; inner.object)
                            foreach(string varIndex, expr; innerJson)
                                setVarMonitorAdapterDynamic(typeName, to!ubyte(varIndex), expr.str);
                        break;

                    case configAISensorNamesKey:
                        foreach(string pin, name; inner.object)
                            setAISensorName(to!ubyte(pin), name.str);
                        break;

                    case configVarSensorNamesKey:
                        foreach(string typeName, innerJson; inner.object)
                            foreach(string varIndex, name; innerJson)
                                setVarMonitorSensorNameDynamic(typeName, to!ubyte(varIndex), name.str);
                        break;

                    default:
                        debug writefln("Unexpected entry with key '%s' found
                        in configuration JSON. Ignoring entry.", key);
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

        // AI value adapters
        if(AIValueAdapters.length > 0)
        {
            JSONValue json = JSONValue(emptyJson);

            foreach(pin, adapter; AIValueAdapters)
                json.object[to!string(pin)] = JSONValue(adapter.expression);

            config.object[configAIAdaptersKey] = json;
        }

        // PWM Out Average value adapters
        if(PWMOutAvgValueAdapters.length > 0)
        {
            JSONValue json = JSONValue(emptyJson);

            foreach(pin, adapter; PWMOutAvgValueAdapters)
                json.object[to!string(pin)] = JSONValue(adapter.expression);

            config.object[configPWMOutAvgAdaptersKey] = json;
        }

        // VarMonitor value adapters
        {
            JSONValue varAdapters = JSONValue(emptyJson);
            bool anyWritten = false;

            foreach(T; VarMonitorTypes)
            {
                alias varMonitorAdapters = varMonitorValueAdapters!T;

                if(varMonitorAdapters.length > 0)
                {
                    anyWritten = true;
                    JSONValue json = JSONValue(emptyJson);

                    foreach(varIndex, adapter; varMonitorAdapters)
                        json.object[to!string(varIndex)] = JSONValue(adapter.expression);

                        varAdapters.object[T.stringof] = json;
                }
            }

            if(anyWritten)
                config.object[configVarAdaptersKey] = varAdapters;
        }

        // AI sensor names
        if(AISensorNames.length > 0)
        {
            JSONValue json = JSONValue(emptyJson);

            foreach(pin, name; AISensorNames)
                json.object[to!string(pin)] = JSONValue(name);

            config.object[configAISensorNamesKey] = json;
        }

        // VarMonitor sensor names
        {
            JSONValue varNames = JSONValue(emptyJson);
            bool anyWritten = false;

            foreach(T; VarMonitorTypes)
            {
                alias varMonitorNames = varMonitorSensorNames!T;

                if(varMonitorNames.length > 0)
                {
                    anyWritten = true;
                    JSONValue typeMonitorNamesJSON = JSONValue(emptyJson);

                    foreach(varIndex, name; varMonitorNames)
                        typeMonitorNamesJSON.object[to!string(varIndex)] = JSONValue(name);

                    varNames.object[T.stringof] = typeMonitorNamesJSON;
                }
            }

            if(anyWritten)
                config.object[configVarSensorNamesKey] = varNames;
        }

        return config.toPrettyString();
    }

    private alias varMonitorValueAdapters(T) = Alias!(mixin(getVarMonitorValueAdaptersName!T));
    private alias varMonitorSensorNames(T) =  Alias!(mixin(getVarMonitorSensorNamesName!T));
}

//Clean this
private pure string unrollVariableValueAdapters(VarTypes...)()
{
    string unroll = "";

    foreach(T; VarTypes)
        unroll ~= getVarMonitorValueAdaptersType!T ~ " " ~ getVarMonitorValueAdaptersName!T ~ ";\n";

    return unroll;
}

private enum getVarMonitorValueAdaptersType(VarType) = "ValueAdapter!(" ~ VarType.stringof ~ ")[ubyte]";
private enum getVarMonitorValueAdaptersName(VarType) = VarType.stringof ~ "ValueAdapters";

private enum getVarMonitorSensorNamesName(VarType) = VarType.stringof ~ "SensorNames";

private pure string unrollVarMonitorSensorNames(VarTypes...)()
{
    string unroll = "";

    foreach(T; VarTypes)
        unroll ~= "string[ubyte] " ~ getVarMonitorSensorNamesName!T ~ ";\n";

    return unroll;
}
