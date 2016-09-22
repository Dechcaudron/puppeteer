module puppeteer.puppet_link.is_ai_monitor_listener;

enum isAIMonitorListener(T) = is(typeof(
{
    T listener;
    listener.onAIUpdate(ubyte.init /* pin */, float.init /* value */):
}()));
