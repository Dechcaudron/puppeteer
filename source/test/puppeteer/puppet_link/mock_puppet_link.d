module test.puppeteer.puppet_link.mock_puppet_link;

import puppeteer.puppet_link.is_puppet_link;

public shared class MockPuppetLink(AIMonitorListenerT, IVMonitorListenerT, IVTypes...)
{
    static assert(isPuppetLink!(shared typeof(this),
                                AIMonitorListenerT,
                                IVMonitorListenerT));

    private bool communicationOpen;
    @property bool isCommunicationOpen()
    {return communicationOpen;}

    private AIMonitorListenerT _AIMonitorListener;
    @property void AIMonitorListener(AIMonitorListenerT listener)
    {_AIMonitorListener = listener;}

    private IVMonitorListenerT _IVMonitorListener;
    @property void IVMonitorListener (IVMonitorListenerT listener)
    {_IVMonitorListener = listener;}

    private bool[ubyte] AIMonitors;

    

    void startCommunication()
    {
        communicationOpen = true;
    }

    void endCommunication()
    {
        communicationOpen = false;
    }

    void readPuppet(long communicationTimeMillis)
    {

    }

    void setAIMonitor(ubyte pin, bool monitor)
    {

    }

    void setIVMonitor(VarMonitorTypeCode varMonitorTypeCode, ubyte varIndex, bool monitor)
    {

    }

    void setPWMOut(ubyte pin, ubyte value)
    {

    }
}
