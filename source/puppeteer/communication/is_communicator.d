module puppeteer.communication.is_communicator;

import puppeteer.puppeteer;

alias OnAIUpdateCallback = void delegate (ubyte /* pin */, float /* value */, long /* communicationTimeMillis */) shared ;
alias OnIVUpdateCallback(T) = void delegate (ubyte /* varIndex */, T /* value */, long /* communicationTimeMillis */) shared;

enum isCommunicator(T, IVTypes...) = is(typeof(
{
    T communicator;

    bool b1 = communicator.startCommunication!( /* this is confusing */ )
                                              (string.init /* devFilename */,
                                              BaudRate.init,
                                              Parity.init,
                                              string.init /* logFilename */);
    communicator.endCommunication();
    bool b2 = communicator.isCommunicationOngoing;

    communicator.setAIMonitor(ubyte.init /* pin */, bool.init /* monitor */);
    communicator.setOnAIUpdateCallback(OnAIUpdateCallback.init /* callback */);

    foreach(IVType; IVTypes)
    {
        communicator.setIVMonitor!IVType(ubyte.init /* varIndex */, bool.init /* monitor */);
        communicator.setOnIVUpdateCallback!IVType((OnIVUpdateCallback!IVType).init /* callback */);
    }

    communicator.setPWMValue(ubyte.init /* pin */, ubyte.init /* value */);
}()));
