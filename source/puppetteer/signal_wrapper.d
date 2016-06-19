module puppeteer.signal_wrapper;

import puppeteer.signal;
import std.stdio;
import core.atomic : atomicOp;

//TODO: life would be so much easier if this class could be shared :)
package synchronized class SignalWrapper(T1...)
{
    private shared mixin Signal!T1 signal;
    private shared int _listeners = 0;

    public void addListener(void delegate(T1) shared listener) shared
    {
        _listeners.atomicOp!"+="(1);
        signal.connect(listener);
    }

    public void removeListener(void delegate(T1) shared listener) shared
    {
        _listeners.atomicOp!"-="(1);
        signal.disconnect(listener);
    }

    public void emit(T1 args) shared
    {
        signal.emit(args);
    }

    @property
    public int listenersNumber() shared
    {
        return _listeners;
    }
}
