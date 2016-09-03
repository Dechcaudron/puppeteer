module puppeteer.configuration.iconfiguration;

import std.stdio;
import std.exception;

public shared interface IConfiguration(VarMonitorTypes...)
{
    void setAIValueAdapterExpression(ubyte pin, string adapterExpression);
    string getAIValueAdapterExpression(ubyte pin);
    float adaptAIValue(ubyte pin, float value);

    void setAISensorName(ubyte pin, string name);
    string getAISensorName(ubyte pin) const;

    string save() const
        out(s){assert(s !is null);}
    void save(File sinkFile, bool flush = true) const;
    void load(string configString)
        in{assert(configString !is null);}
    void load(File configFile);


    //pragma(msg, unrollHelperMethodDeclarations!VarMonitorTypes);
    mixin(unrollHelperMethodDeclarations!VarMonitorTypes);


    final void setVarMonitorValueAdapterExpression(VarType)(ubyte varIndex, string adapterExpression)
    {
        mixin(generateHelperMethodName!VarType("setVarMonitorValueAdapterExpression"))(varIndex, adapterExpression);
    }

    final string getVarMonitorValueAdapterExpression(VarType)(ubyte varIndex) const
    {
        return mixin(generateHelperMethodName!VarType("getVarMonitorValueAdapterExpression"))(varIndex);
    }

    final VarType adaptVarMonitorValue(VarType)(ubyte varIndex, VarType value) const
    {
        return mixin(generateHelperMethodName!VarType("adaptVarMonitorValue"))(varIndex, value);
    }

    final void setVarMonitorSensorName(VarType)(ubyte varIndex, string name)
    {
        mixin(generateHelperMethodName!VarType("setVarMonitorSensorName"))(varIndex, name);
    }

    final string getVarMonitorSensorName(VarType)(ubyte varIndex) const
    {
        return mixin(generateHelperMethodName!VarType("getVarMonitorSensorName"))(varIndex);
    }
}

private pure string generateHelperMethodName(VarType)(string methodName)
{
    return methodName ~ "_" ~ VarType.stringof;
}

private pure string generateHelperMethodSignature(VarType)(string returnType, string methodName, string arguments, string attributes = "")
{
    return returnType ~ " " ~ generateHelperMethodName!VarType(methodName) ~ arguments ~ " " ~ attributes;
}

private pure string unrollHelperMethodDeclarations(VarMonitorTypes...)()
{
    string unroll = "";

    foreach(T; VarMonitorTypes)
    {
        unroll ~= generateHelperMethodSignature!T("void",
                    "setVarMonitorValueAdapterExpression",
                    "(ubyte varIndex, string adapterExpression)") ~ ";\n";
        unroll ~= generateHelperMethodSignature!T("string",
                    "getVarMonitorValueAdapterExpression",
                    "(ubyte varIndex)", "const") ~ ";\n";
        unroll ~= generateHelperMethodSignature!T(T.stringof,
                    "adaptVarMonitorValue",
                    "(ubyte varIndex, " ~ T.stringof ~ " value)",
                     "const") ~ ";\n";
        unroll ~= generateHelperMethodSignature!T("void",
                    "setVarMonitorSensorName",
                    "(ubyte varIndex, string name)") ~ ";\n";
        unroll ~= generateHelperMethodSignature!T("string",
                    "getVarMonitorSensorName",
                    "(ubyte varIndex)",
                    "const") ~ ";\n";
    }

    return unroll;
}

public pure string unrollHelperMethods(VarMonitorTypes...)()
{
    string unroll = "";

    foreach(T; VarMonitorTypes)
    {
        unroll ~= generateHelperMethodSignature!T("void",
                    "setVarMonitorValueAdapterExpression",
                    "(ubyte varIndex, string adapterExpression)") ~
                    "{setVarMonitorValueAdapterExpression!" ~ T.stringof ~
                    "(varIndex, adapterExpression);}\n";
        unroll ~= generateHelperMethodSignature!T("string",
                    "getVarMonitorValueAdapterExpression",
                    "(ubyte varIndex)", "const") ~
                    "{return getVarMonitorValueAdapterExpression!" ~ T.stringof ~
                    "(varIndex);}\n";
        unroll ~= generateHelperMethodSignature!T(T.stringof,
                    "adaptVarMonitorValue",
                    "(ubyte varIndex, " ~ T.stringof ~ " value)", "const") ~
                    "{return adaptVarMonitorValue!" ~ T.stringof ~
                    "(varIndex, value);}\n";
        unroll ~= generateHelperMethodSignature!T("void",
                    "setVarMonitorSensorName",
                    "(ubyte varIndex, string name)") ~
                    "{setVarMonitorSensorName!" ~ T.stringof ~
                    "(varIndex, name);}\n";
        unroll ~= generateHelperMethodSignature!T("string",
                    "getVarMonitorSensorName",
                    "(ubyte varIndex)", "const") ~
                    "{return getVarMonitorSensorName!" ~ T.stringof ~
                    "(varIndex);}\n";
    }

    return unroll;
}
