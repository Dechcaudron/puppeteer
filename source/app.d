import std.stdio;
import std.exception;
import std.getopt;
import std.file;
import std.concurrency;
import std.conv;
import std.datetime;
import std.string;
import std.format;

import core.thread;

import puppeteer.arduino_driver;
import puppeteer.serial.BaudRate;
import puppeteer.serial.Parity;

__gshared StopWatch timer;

alias Puppeteer = ArduinoDriver!(int);

void main(string[] args)
{
	string devFilename = "";
	string outFilename = "puppeteerOut.txt";

	getopt(args,
		"dev|d", &devFilename,
		"out|o", &outFilename);

	enforce(devFilename != "" && exists(devFilename), "Please select an existing device using --dev [devicePath]");

	writeln("Opening dev file "~devFilename);
	Puppeteer driver = new Puppeteer(devFilename, Parity.none, BaudRate.B9600);
	driver.addVariableListener!bool(0, null);

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
			int pinInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &pinInput);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

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
			int pinInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &pinInput);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

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

			int pinInput = -1;
			ubyte pwmValue;
			string input = readln().chomp();
			formattedRead(input, " %s-%s", &pinInput, &pwmValue);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			writeln("Setting PWM pin ", pin, " to value ", pwmValue);
			driver.setPWM(pin, pwmValue);
		}

		menu : while(true)
		{
			writeln("------");
			writeln("Available options:");
			with(Options)
			{
				printOption(start, "Start communication");
				printOption(stop, "Stop communication");
				printOption(monitor, "Monitor analog input");
				printOption(stopMonitor, "Stop monitoring analog input");
				printOption(pwm, "Set PWM output");
				printOption(exit, "Exit");
			}
			writeln();
			write("Select an option: ");

			int option = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &option);

			void printCommunicationRequired()
			{
				writeln("An established communication is required for this option.");
			}

			switch(option) with (Options)
			{
				case start:
					if(!driver.isCommunicationEstablished)
					{
						writeln("Establishing communication with puppet...");
						if(driver.startCommunication())
						{
							writeln("Communication established.");
							timer.reset();
							timer.start();
						}
						else
							writeln("Could not establish communication with puppet.");
					}
					else
						writeln("Communication is already established.");

					break;

				case stop:
					if(driver.isCommunicationEstablished)
					{
						driver.endCommunication();
						writeln("Communication ended.");
						timer.stop();
					}
					else
						writeln("Communication has not been established yet.");
					break;

				case monitor:
					if(driver.isCommunicationEstablished)
						addMonitor();
					else
						printCommunicationRequired();
					break;

				case stopMonitor:
					if(driver.isCommunicationEstablished)
						removeMonitor();
					else
						printCommunicationRequired();
					break;

				case pwm:
					if(driver.isCommunicationEstablished)
						setPWM();
					else
						printCommunicationRequired();
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
					writeln("Please select a valid option.");
			}
		}
	}

	showMenu();
}

class PinListener
{
	Puppeteer driver;
	ubyte pin;
	Tid loggerTid;

	this(Puppeteer driver, ubyte pin, Tid loggerTid)
	{
		this.driver = driver;
		this.pin = pin;
		this.loggerTid = loggerTid;
	}

	void listenerMethod(ubyte pin, float value)
	{
		loggerTid.send(MainMessage(to!string(timer.peek().msecs)~" => Pin "~to!string(pin)~" read "~to!string(value)));
	}

	void addListener()
	{
		driver.addPinListener(pin, &listenerMethod);
	}

	void removeListener()
	{
		driver.removePinListener(pin, &listenerMethod);
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
