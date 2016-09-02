module puppeteer.communication.icommunicator;

import puppeteer.puppeteer;

import std.exception;

public interface ICommunicator(VarMonitorTypes...)
{
    @property
    bool isCommunicationOngoing() shared;

    bool startCommunication(shared Puppeteer!VarMonitorTypes puppeteer, string devFilename, BaudRate baudRate, Parity parity, string logFilename) shared;
    void endCommunication() shared;

    void setPWMValue(ubyte pin, ubyte pwmValue) shared;

    void changeAIMonitorStatus(ubyte pin, bool shouldMonitor) shared;
    void changeVarMonitorStatus(VarType)(ubyte varIndex, bool shouldMonitor) shared
    {
        mixin(changeVarMonitorStatusMethodName!VarType ~ "(varIndex, shouldMonitor);");
    }

    mixin(unrollChangeVarMonitorStatusMethodDeclarations!VarMonitorTypes());

    protected final void enforceCommunicationOngoing() shared
    {
        enforce!CommunicationException(isCommunicationOngoing);
    }
}

public pure string unrollChangeVarMonitorStatusMethods(VarMonitorTypes...)()
{
    string unroll = "";

    foreach(T; VarMonitorTypes)
    {
        unroll ~= changeVarMonitorStatusMethodSignature!T ~ "{ changeVarMonitorStatus!" ~ T.stringof ~ "(varIndex, shouldMonitor);} \n";
    }

    return unroll;
}

private enum changeVarMonitorStatusMethodName(VarType) = "changeVarMonitorStatus_" ~ VarType.stringof;
private enum changeVarMonitorStatusMethodSignature(VarType) = "void " ~ changeVarMonitorStatusMethodName!VarType ~ "(ubyte varIndex, bool shouldMonitor) shared";

private pure string unrollChangeVarMonitorStatusMethodDeclarations(VarMonitorTypes...)()
{
    string unroll = "";

    foreach(T; VarMonitorTypes)
        unroll ~= changeVarMonitorStatusMethodSignature!T ~ ";\n";

    return unroll;
}
