module test.puppeteer.communication.broken_communicator;

import puppeteer.puppeteer;

import puppeteer.communication.icommunicator;
import puppeteer.communication.communication_exception;

public shared class BrokenCommunicator(VarMonitorTypes...) : ICommunicator!VarMonitorTypes
{
    @property
    bool isCommunicationOngoing()
    {
        return false;
    }

    bool startCommunication(shared Puppeteer!VarMonitorTypes puppeteer, string devFilename, BaudRate baudRate, Parity parity, string logFilename)
    {
        return false;
    }

    void endCommunication()
    {
        throw new CommunicationException("Broken Communicator is always broken");
    }

    void setPWMValue(ubyte pin, ubyte pwmValue) {enforceCommunicationOngoing();}

    void changeAIMonitorStatus(ubyte pin, bool shouldMonitor) {enforceCommunicationOngoing();}

    mixin (unrollChangeVarMonitorStatusMethods!VarMonitorTypes());
    void changeVarMonitorStatus(VarType)(ubyte varIndex, bool shouldMonitor) {enforceCommunicationOngoing();}
}
