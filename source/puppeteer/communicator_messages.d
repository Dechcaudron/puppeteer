module puppeteer.communicator_messages;

private struct CommunicationEstablishedMessage
{
    bool success;

    this(bool success)
    {
        this.success = success;
    }
}

private struct CommunicationEndedMessage
{

}

private struct EndCommunicationMessage
{

}

private struct PinMonitorMessage
{
    enum Action
    {
        start,
        stop
    }

    private Action action;
    private ubyte pin;

    this(Action action, ubyte pin)
    {
        this.action = action;
        this.pin = pin;
    }
}

private struct VarMonitorMessage
{
    import puppeteer.var_monitor_utils : VarMonitorTypeCode;

    enum Action
    {
        start,
        stop
    }

    private Action action;
    private ubyte varIndex;
    private VarMonitorTypeCode varTypeCode;

    this(Action action, ubyte varIndex, VarMonitorTypeCode varTypeCode)
    {
        this.action = action;
        this.varIndex = varIndex;
        this.varTypeCode = varTypeCode;
    }
}

private struct SetPWMMessage
{
    ubyte pin;
    ubyte value;

    this(ubyte pin, ubyte value)
    {
        this.pin = pin;
        this.value = value;
    }
}
