module puppeteer.puppet_link.is_puppet_link;

import puppeteer.puppet_link.is_ai_monitor_listener;
import puppeteer.puppet_link.is_iv_monitor_listener;

import puppeteer.var_monitor_utils;

enum isPuppetLink(T, AIMonitorListenerT, IVMonitorListenerT) = is(typeof(
{
    T puppetLink;

    puppetLink.startCommunication();
    puppetLink.endCommunication();

    puppetLink.readPuppet(long.init /* communicationTimeMillis */);

    bool a = puppetLink.isCommunicationOpen;

    puppetLink.setAIMonitor(ubyte.init /* pin */, bool.init /* monitor */);
    puppetLink.AIMonitorListener = AIMonitorListenerT.init /* listener */;

    puppetLink.setIVMonitor(VarMonitorTypeCode.init /* IV type */, ubyte.init /* var index */, bool.init /* monitor */);
    puppetLink.IVMonitorListener = IVMonitorListenerT.init /* listener */;

    puppetLink.setPWMOut(ubyte.init /* pin */, ubyte.init /* value */);
}
())) &&
isAIMonitorListener!AIMonitorListenerT &&
isIVMonitorListener!IVMonitorListenerT;
