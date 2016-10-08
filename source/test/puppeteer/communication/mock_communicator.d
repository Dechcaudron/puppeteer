module test.puppeteer.communication.mock_communicator;

import puppeteer;

public shared class MockCommunicator(PuppetLinkT, IVTypes...)
if(isPuppetLink!(PuppetLinkT, shared typeof(this), shared typeof(this)))
{
    static assert(isCommunicator!(shared typeof(this), IVTypes));

    private bool communicationOngoing;

    @property
    bool isCommunicationOngoing()
    {
        return communicationOngoing;
    }

    bool startCommunication(string devFilename, BaudRate baudrate, Parity parity)
    {
        enforce(!communicationOngoing);
    }

    void endCommunication()
    {
        enforceCommunicationOngoing();
    }

    void setAIMonitor(ubyte pin, bool monitor)
    {

    }

    void setOnAIUpdateCallback(OnAIUpdateCallback callback)
    {

    }

    void setIVMonitor(IVType)(ubyte varIndex, bool monitor)
    {

    }

    void setOnIVUpdateCallback(IVType)(OnIVUpdateCallback!IVType callback)
    {

    }

    void setPWMValue(ubyte pin, ubyte value)
    {

    }

    private void enforceCommunicationOngoing()
    {
        enforce(communicationOngoing);
    }
}
