module puppeteer.puppet_link.is_puppet_link;

import puppeteer.puppet_link.is_ai_monitor_listener;
import puppeteer.puppet_link.is_iv_monitor_listener;

import puppeteer.var_monitor_utils;

alias OnAIUpdateCallback = void delegate (ubyte /* pin */,
                                          float /* value */,
                                          long /* communicationTimeMillis */);

alias OnIVUpdateCallback(IVType) = void delegate (ubyte /* varIndex */,
                                                  IVType /* value */,
                                                  long /* communicationTimeMillis */);

enum isPuppetLink(T, IVTypes...) = is(typeof(
{
    T puppetLink;

    puppetLink.startCommunication();
    puppetLink.endCommunication();

    puppetLink.readPuppet(long.init /* communicationTimeMillis */);

    bool a = puppetLink.isCommunicationOpen;

    puppetLink.setAIMonitor(ubyte.init /* pin */, bool.init /* monitor */);
    puppetLink.AIMonitorCallback = OnAIUpdateCallback.init /* callback */;

    puppetLink.setIVMonitor(VarMonitorTypeCode.init /* IV type */, ubyte.init /* var index */, bool.init /* monitor */);
    puppetLink.IVMonitorListener = IVMonitorListenerT.init /* listener */;

    puppetLink.setPWMOut(ubyte.init /* pin */, ubyte.init /* value */);
}
())) &&
isAIMonitorListener!AIMonitorListenerT &&
isIVMonitorListener!IVMonitorListenerT;
