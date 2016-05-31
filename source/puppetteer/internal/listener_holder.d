module puppetteer.internal.listener_holder;

import puppetteer.arduino_driver : readListenerDelegate;

class ListenerHolder
{
	private shared readListenerDelegate[] listeners;

	this(readListenerDelegate listener) shared
	{
		listeners ~= listener;
	}

	public void add(readListenerDelegate listener) shared
	{
		listeners ~= listener;
	}

	public void remove(readListenerDelegate listener) shared
	{
		import std.algorithm.mutation;

		listeners = listeners.remove!(a => a is listener);
	}

	public shared(const(readListenerDelegate[])) getListeners() const shared
	{
		return listeners;
	}

	public size_t getListenersNumber() const shared
	{
		return listeners.length;
	}
}
