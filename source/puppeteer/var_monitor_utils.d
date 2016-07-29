module puppeteer.var_monitor_utils;

import std.typecons : Tuple;

private enum VarMonitorTypeCode : byte
{
    _short = 0x0,
}

public enum isVarMonitorTypeSupported(VarType) = __traits(compiles, getVarMonitorTypeCode!VarType) && __traits(compiles, varMonitorSensorDefaultName!VarType);
unittest
{
    assert(isVarMonitorTypeSupported!short);
    assert(!isVarMonitorTypeSupported!float);
    assert(!isVarMonitorTypeSupported!void);
}

private alias getVarMonitorTypeCode(VarType) = Alias!(mixin(VarMonitorTypeCode.stringof ~ "._" ~ VarType.stringof));
unittest
{
    assert(getVarMonitorTypeCode!short == VarMonitorTypeCode._short);
}

private enum VarMonitorSensorDefaultName
{
    _short = "Int16"
}

private alias varMonitorSensorDefaultName(VarMonitorType) = Alias!(mixin(VarMonitorSensorDefaultName.stringof ~ "._" ~ VarMonitorType.stringof));
unittest
{
    assert(varMonitorSensorDefaultName!short == VarMonitorSensorDefaultName._short);
}

private alias getVarMonitorType(VarMonitorTypeCode typeCode) = Alias!(mixin("Alias!(" ~ to!string(typeCode)[1..$] ~ ")"));
unittest
{
    with(VarMonitorTypeCode)
    {
        assert(is(getVarMonitorType!_short == short));
    }
}
