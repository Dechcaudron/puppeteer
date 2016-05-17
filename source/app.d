import std.stdio;
import pupetteer.arduino_driver;
import pupetteer.serial.BaudRate;
import pupetteer.serial.Parity;

void main()
{
	ArduinoDriver driver = new ArduinoDriver("", Parity.none, BaudRate.B9600);
	TestClass test = new TestClass(driver);
	driver.startCommunication();

	int readInt;

	do
	{
		write("Type 0 to exit: ");
		readf(" %s", &readInt);

	}while(readInt != 0);

	driver.endCommunication();

	
}

class TestClass
{
	this(ArduinoDriver driver)
	{
		driver.listen(0, &listener);
	}

	void listener(ubyte pin, float value) shared
	{
		writeln("Test read pin ",pin, " and value ",value);
	}
}
