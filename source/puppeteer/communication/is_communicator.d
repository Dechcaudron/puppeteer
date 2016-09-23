module puppeteer.communication.is_communicator;

import puppeteer.puppeteer;

enum isCommunicator(T, IVTypes...) = //__traits(compiles,
{
    pragma(msg, T.stringof);
    T communicator;

    bool b1 = communicator.startCommunication((shared Puppeteer!(T, IVTypes)).init /* puppeteer */,
                                    string.init /* devFilename */,
                                    BaudRate.init,
                                    Parity.init,
                                    string.init /* logFilename */);
    communicator.endCommunication();
    bool b2 = communicator.isCommunicationOngoing;

    communicator.setAIMonitor(ubyte.init /* pin */, bool.init /* monitor */);

    foreach(IVType; IVTypes)
        communicator.setIVMonitor!IVType(ubyte.init /* varIndex */, bool.init /* monitor */);

    communicator.setPWMValue(ubyte.init /* pin */, ubyte.init /* value */);
    pragma(msg, "end of " ~ T.stringof);
}
();
