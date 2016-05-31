import std.stdio;
import core.thread;
import core.time;
import puppetteer.arduino_driver;
import puppetteer.serial.BaudRate;
import puppetteer.serial.Parity;

void main()
{
	ArduinoDriver driver = new ArduinoDriver("/dev/ttyACM0", Parity.none, BaudRate.B9600);
	TestClass test = new TestClass(driver, 0);
	TestClass test2 = new TestClass(driver, 1);
	driver.startCommunication();

    Thread.sleep(dur!"seconds"(2));
    
    TestClass test3 = new TestClass(driver, 2);
    
	int readInt;

	do
	{
		writeln("Type 0 to exit: ");
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
