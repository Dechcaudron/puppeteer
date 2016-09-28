module puppeteer.puppet_link.is_iv_monitor_listener;

enum isIVMonitorListener(T, IVTypes...) = is(typeof(
{
    T listener;
    foreach(IVType; IVTypes)
        listener.onIVUpdate!IVType /* var type on D */
                                  (ubyte.init /* var index */,
                                  IVType.init /* value */,
                                  long.init /* communicationTimeMillis */);
}()));
