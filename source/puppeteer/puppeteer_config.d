module puppeteer.puppeteer_config;

import puppeteer.var_monitor_utils;
import puppeteer.value_adapter;
import puppeteer.exception.invalid_configuration_exception;

import std.meta : allSatisfy;

shared class PuppeteerConfig(VarMonitorTypes...)
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

    public bool saveConfig(string targetPath)
    in
    {
        assert(targetPath !is null);
        assert(targetPath != "");
    }
    body
    {
        debug writeln("Trying to save configuration to " ~ targetPath);
        string config = generateConfigString();

        File f = File(targetPath, "w");
        scope(exit) f.close();

        if(!f.isOpen)
            return false;

        f.write(config);

        debug writeln("Success!");
        return true;
    }

    public bool loadConfig(string sourcePath)
    in
    {
        assert(sourcePath !is null);
        assert(sourcePath != "");
    }
    body
    {
        debug writeln("Trying to load configuration from path ",sourcePath);
        File f = File(sourcePath, "r");
        scope(exit) f.close();

        if(!f.isOpen)
            return false;

        string content;
        f.readf("%s", &content);

        applyConfig(content);
        debug writeln("Success!");

        return true;
    }

    private void applyConfig(string configStr)
    {
        import std.json;

        JSONValue top = parseJSON(configStr);

        JSONValue aiAdapters = top[configAIAdaptersKey].object;

        foreach(string key, expr; aiAdapters)
        {
            setAIValueAdapter(to!ubyte(key), expr.str);
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

        foreach(pin, adapter; AIValueAdapters)
        {
            AIAdapters.object[to!string(pin)] = JSONValue(adapter.expression);
        }

        config.object[configAIAdaptersKey] = AIAdapters;

        JSONValue varAdapters = JSONValue(emptyJson);

        foreach(member; __traits(allMembers, VarMonitorTypeCode))
        {
            static if(canMonitor!(getVarMonitorType!(Alias!(mixin("VarMonitorTypeCode." ~ member)))))
            {
                alias varMonitorAdapters = Alias!(mixin(getVarMonitorValueAdaptersName!(getVarMonitorType!(Alias!(mixin("VarMonitorTypeCode." ~ member))))));

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
