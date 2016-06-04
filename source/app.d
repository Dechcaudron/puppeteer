import std.stdio;
import std.exception;
import std.getopt;
import std.file;
import std.concurrency;
import std.conv;

import core.thread;
import core.time : dur;


import puppetteer.arduino_driver;
import puppetteer.serial.BaudRate;
import puppetteer.serial.Parity;

void main(string[] args)
{
	string devFilename = "";
	string outFilename = "puppetteerOut.txt";

	getopt(args,
		"dev|d", &devFilename,
		"out|o", &outFilename);

	enforce(devFilename != "" && exists(devFilename), "Please select an existing device using --dev [devicePath]");

	writeln("Opening dev file "~devFilename);
	ArduinoDriver driver = new ArduinoDriver(devFilename, Parity.none, BaudRate.B9600);

	Tid loggerTid = spawn(
		(string outFilename)
		{
			bool shouldContinue = true;

			File outFile = File(outFilename, "w");

			while(shouldContinue)
			{
				receive(
				(MainMessage message)
				{
					if(message.message != "END")
					{
						outFile.writeln(message.message);
						outFile.flush();
					}
					else
					{
						shouldContinue = false;
						outFile.close();
					}
				});
			}
		}, outFilename);

	void showMenu()
	{
		enum Options
		{
			start,
			stop,
			monitor,
			stopMonitor,
			pwm,
			exit
		}

		void printOption(Options option, string optionMsg)
		{
			writeln(to!string(int(option)) ~ " - " ~ optionMsg);
		}

		PinListener[int] listeners;

		void addMonitor()
		{
			write("Which pin do you want to monitor? (-1 to cancel): ");
			int input;
			readf(" %s", &input);

			if(input < 0)
				return;

			ubyte pin = to!ubyte(input);

			if(pin !in listeners)
			{
				listeners[pin] = new PinListener(driver, pin, loggerTid);
				listeners[pin].addListener();
				writeln("Monitoring pin ",pin);
			}
			else
				writeln("That pin is already being monitored.");
		}

		void removeMonitor()
		{
			write("Which pin do you want to stop monitoring? (-1 to cancel): ");
			int input;
			readf(" %s", &input);

			if(input < 0)
				return;

			ubyte pin = to!ubyte(input);

			if(pin in listeners)
			{
				listeners[pin].removeListener();
				listeners.remove(pin);
				writeln("Stopped monitoring pin ",pin);
			}
			else
				writeln("That pin is not being monitored.");
		}

		void setPWM()
		{
			write("Introduce pin and PWM value [pin-value] (-1 to cancel): ");

			int pinInput;
			ubyte pwmValue;
			readf(" %s-%s", &pinInput, &pwmValue);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			writeln("Setting PWM pin", pin, "to value", pwmValue);
			driver.setPWM(pin, pwmValue);
		}

		menu : while(true)
		{
			writeln("------");
			writeln("Choose an option:");
			with(Options)
			{
				printOption(start, "Start communication");
				printOption(stop, "Stop communication");
				printOption(monitor, "Monitor analog input");
				printOption(stopMonitor, "Stop monitoring analog input");
				printOption(pwm, "Set PWM output");
				printOption(exit, "Exit");
			}

			int option;

			readf(" %s", &option);

			switch(option) with (Options)
			{
				case start:
					writeln("Establishing communication with puppet...");
					if(driver.startCommunication())
						writeln("Communication established.");
					else
						writeln("Could not establish communication with puppet.");
					break;

				case stop:
					driver.endCommunication();
					writeln("Communication ended.");
					break;

				case monitor:
					if(driver.isCommunicationEstablished)
						addMonitor();
					break;

				case stopMonitor:
					if(driver.isCommunicationEstablished)
						removeMonitor();
					break;

				case pwm:
					if(driver.isCommunicationEstablished)
						setPWM();
					break;

				case exit:
					if(driver.isCommunicationEstablished)
					{
						writeln("Finishing communication with puppet...");
						driver.endCommunication();
					}
					loggerTid.send(MainMessage("END"));
					break menu;

				default:
					writeln(to!string(option)~" is not a valid option");
			}
		}
	}

	showMenu();
}

class PinListener
{
	ArduinoDriver driver;
	ubyte pin;
	Tid loggerTid;

	this(ArduinoDriver driver, ubyte pin, Tid loggerTid)
	{
		this.driver = driver;
		this.pin = pin;
		this.loggerTid = loggerTid;
	}

	void listenerMethod(ubyte pin, float value)
	{
		loggerTid.send(MainMessage("Pin "~to!string(pin)~" read "~to!string(value)));
	}

	void addListener()
	{
		driver.addListener(pin, &listenerMethod);
	}

	void removeListener()
	{
		driver.removeListener(pin, &listenerMethod);
	}
}

struct MainMessage
{
	private string message;

	this(string message)
	{
		this.message = message;
	}
}
