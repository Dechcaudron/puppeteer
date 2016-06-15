module puppeteer.signal_wrapper;

import std.stdio;
import std.signals;

//TODO: life would be so much easier if this class could be shared :)
package class SignalWrapper(T1...)
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
