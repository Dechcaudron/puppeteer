import puppeteer.puppeteer;

class DummyListener(T...)
{
	Puppeteer!T puppeteer;

	this(Puppeteer!T puppeteer)
	{
		this.puppeteer = puppeteer;
	}

	void pinListenerMethod(ubyte pin, float receivedValue, float adaptedValue, long msecs) shared
	{
		//Dummy method
	}

	void varListenerMethod(VarType)(ubyte varIndex, VarType receivedValue, VarType adaptedValue, long msecs) shared
	{
		//Dummy method
	}

	void addPinListener(ubyte pin)
	{
		puppeteer.addPinListener(pin, &pinListenerMethod);
	}

	void removePinListener(ubyte pin)
	{
		puppeteer.removePinListener(pin, &pinListenerMethod);
	}

	void addVarListener(VarType)(ubyte varIndex)
	{
		puppeteer.addVariableListener(varIndex, &varListenerMethod!VarType);
	}

	void removeVarListener(VarType)(ubyte varIndex)
	{
		puppeteer.removeVariableListener(varIndex, &varListenerMethod!VarType);
	}
}
