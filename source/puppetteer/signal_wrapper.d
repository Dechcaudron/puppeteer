module puppeteer.signal_wrapper;

import puppeteer.signal;
import std.stdio;

//TODO: life would be so much easier if this class could be shared :)
package synchronized class SignalWrapper(T1...)
{
    private shared mixin Signal!T1 signal;

    public void addListener(void delegate(T1) shared listener) shared
    {
        signal.connect(listener);
    }

    public void removeListener(void delegate(T1) shared listener) shared
    {
        signal.disconnect(listener);
    }

    public void emit(T1 args) shared
    {
        signal.emit(args);
    }

    @property
    public size_t listenersNumber() shared
    {
        return slots_idx;
    }
}
