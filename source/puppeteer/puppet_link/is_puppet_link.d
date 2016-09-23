module puppeteer.puppet_link.is_puppet_link;

import puppeteer.puppet_link.is_ai_monitor_listener;
import puppeteer.puppet_link.is_iv_monitor_listener;

enum isPuppetLink(T, AIMonitorListenerT, IVMonitorListenerT, IVTypes...) = is(typeof(
{
    T puppetLink;

    puppetLink.startCommunication();
    puppetLink.endCommunication();

    puppetLink.readPuppet(long.init /* communicationMsTime */);

    puppetLink.isCommunicationOpen is bool.init;

    puppetLink.setAIMonitor(ubyte.init /* pin */, bool.init /* monitor */);
    puppetLink.AIMonitorListener = AIMonitorListenerT.init /* listener */;

    foreach(IVType; IVTypes)
        puppetLink.setIVMonitor!IVType(ubyte.init /* var index */, bool.init /* monitor */);
    puppetLink.IVMonitorListener = IVMonitorListenerT.init /* listener */;

    puppetLink.setPWMOut(ubyte.init /* pin */, ubyte.init /* value */);
}
())) &&
isAIMonitorListener!AIMonitorListenerT &&
isIVMonitorListener!IVMonitorListenerT;
