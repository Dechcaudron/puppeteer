import std.stdio;
import core.thread;
import core.time;
import puppetteer.arduino_driver;
import puppetteer.serial.BaudRate;
import puppetteer.serial.Parity;

void main()
{
	ArduinoDriver driver = new ArduinoDriver("/dev/ttyACM0", Parity.none, BaudRate.B9600);
	driver.startCommunication();

	void t1()
	{
		TestClass test = new TestClass(driver, 3);
		TestClass test2 = new TestClass(driver, 0);
		TestClass test4 = new TestClass(driver, 0);

	    Thread.sleep(dur!"seconds"(1));

	    TestClass test3 = new TestClass(driver, 2);

		Thread.sleep(dur!"seconds"(1));

		writeln("Removing listener on pin 3");
		test.removeListener();
		writeln("Removing one listener on pin 0");
		test2.removeListener();
	}

	void t2()
	{
		TestClass test = new TestClass(driver, 0);

		Thread.sleep(dur!"seconds"(2));

		driver.setPWM(3, 50);

		writeln("Pin 3 set to 0");

		Thread.sleep(dur!"seconds"(2));

		driver.setPWM(3, 200);

		writeln("Pin 3 set to 255");
	}

	t2();

	int readInt;

	do
	{
        readf(" %s", &readInt);

	}while(readInt != 0);

	driver.endCommunication();
}

class TestClass
{
	ArduinoDriver driver;
	ubyte pin;

	this(ArduinoDriver driver, ubyte pin)
	{
		driver.addListener(pin, &listener);
		this.driver = driver;
		this.pin = pin;
	}

	void listener(ubyte pin, float value) shared
	{
		writeln("Test read pin ",pin, " and value ",value);
	}

	void removeListener()
	{
		driver.removeListener(pin, &listener);
	}
}
