module puppeteer.communication.is_communicator;

import puppeteer.puppeteer;

alias OnAIUpdateCallback = void delegate (ubyte /* pin */, float /* value */, long /* communicationTimeMillis */) shared ;
alias OnIVUpdateCallback(T) = void delegate (ubyte /* varIndex */, T /* value */, long /* communicationTimeMillis */) shared;

enum isCommunicator(T, IVTypes...) = is(typeof(
{
    T communicator;

    bool communicationStarted = communicator.startCommunication
                                              (string.init /* devFilename */,
                                              BaudRate.init,
                                              Parity.init);
    communicator.endCommunication();
    bool communicationOngoing = communicator.isCommunicationOngoing;

    communicator.setAIMonitor(ubyte.init /* pin */, bool.init /* monitor */);
    communicator.setOnAIUpdateCallback(OnAIUpdateCallback.init /* callback */);

    foreach(IVType; IVTypes)
    {
        communicator.setIVMonitor!IVType(ubyte.init /* varIndex */, bool.init /* monitor */);
        communicator.setOnIVUpdateCallback!IVType((OnIVUpdateCallback!IVType).init /* callback */);
    }

    communicator.setPWMValue(ubyte.init /* pin */, ubyte.init /* value */);
}()));
