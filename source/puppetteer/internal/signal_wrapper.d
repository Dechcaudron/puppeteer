module puppeteer.internal.signal_wrapper;

import std.signals;

class SignalWrapper(T1...)
{
    private mixin Signal!T1 signal;
    private int _listeners = 0;

    public void addListener(void delegate(T1) listener)
    {
        _listeners++;
        signal.connect(listener);
    }

    public void removeListener(void delegate(T1) listener)
    {
        _listeners--;
        signal.disconnect(listener);
    }

    public void emit(T1 args)
    {
        signal.emit(args);
    }

    @property
    public int listenersNumber()
    {
        return _listeners;
    }
}
