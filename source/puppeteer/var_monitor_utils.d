module puppeteer.var_monitor_utils;

import std.typecons;
import std.meta;
import std.conv;

public enum VarMonitorTypeCode : ubyte
{
    _short = 0x0,
}

private enum VarMonitorDefaultSensorName
{
    _short = "Int16"
}

public enum isVarMonitorTypeSupported(VarType) = __traits(compiles, varMonitorTypeCode!VarType) && __traits(compiles, varMonitorDefaultSensorName!VarType);
unittest
{
    assert(isVarMonitorTypeSupported!short);
    assert(!isVarMonitorTypeSupported!float);
    assert(!isVarMonitorTypeSupported!void);
}

package alias varMonitorTypeCode(VarType) = Alias!(to!VarMonitorTypeCode("_" ~ VarType.stringof)); //Alias!(mixin(VarMonitorTypeCode.stringof ~ "._" ~ VarType.stringof));
unittest
{
    assert(varMonitorTypeCode!short == VarMonitorTypeCode._short);
}

package alias varMonitorDefaultSensorName(VarMonitorType) = Alias!(to!VarMonitorDefaultSensorName("_" ~ VarMonitorType.stringof));
unittest
{
    assert(varMonitorDefaultSensorName!short == VarMonitorDefaultSensorName._short);
}

package alias varMonitorType(VarMonitorTypeCode typeCode) = Alias!(mixin("Alias!(" ~ to!string(typeCode)[1..$] ~ ")"));
unittest
{
    with(VarMonitorTypeCode)
    {
        assert(is(varMonitorType!_short == short));
    }
}
