import std.stdio;
import pupetteer.arduino_driver;
import pupetteer.serial.BaudRate;
import pupetteer.serial.Parity;

void main()
{
	ArduinoDriver driver = new ArduinoDriver("/dev/ttyACM0", Parity.none, BaudRate.B9600);
	TestClass test = new TestClass(driver, 0);
	TestClass test2 = new TestClass(driver, 1);
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
	this(ArduinoDriver driver, ubyte pin)
	{
		driver.addListener(pin, &listener);
	}

	void listener(ubyte pin, float value) shared
	{
		writeln("Test read pin ",pin, " and value ",value);
	}
}
