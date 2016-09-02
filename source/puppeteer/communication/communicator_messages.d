module puppeteer.communication.communicator_messages;

package
{
    struct CommunicationEstablishedMessage
    {
        bool success;

        this(bool success)
        {
            this.success = success;
        }
    }

    struct CommunicationEndedMessage
    {

    }

    struct EndCommunicationMessage
    {

    }

    struct PinMonitorMessage
    {
        enum Action
        {
            start,
            stop
        }

        Action action;
        ubyte pin;

        this(Action action, ubyte pin)
        {
            this.action = action;
            this.pin = pin;
        }
    }

    struct VarMonitorMessage
    {
        import puppeteer.var_monitor_utils : VarMonitorTypeCode;

        enum Action
        {
            start,
            stop
        }

        Action action;
        ubyte varIndex;
        VarMonitorTypeCode varTypeCode;

        this(Action action, ubyte varIndex, VarMonitorTypeCode varTypeCode)
        {
            this.action = action;
            this.varIndex = varIndex;
            this.varTypeCode = varTypeCode;
        }
    }

    struct SetPWMMessage
    {
        ubyte pin;
        ubyte value;

        this(ubyte pin, ubyte value)
        {
            this.pin = pin;
            this.value = value;
        }
    }

}
