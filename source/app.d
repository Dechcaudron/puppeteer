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

alias Puppeteer = ArduinoDriver!(short);

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
			startPinMonitor,
			stopPinMonitor,
			startVarMonitor,
			stopVarMonitor,
			pwm,
			exit
		}

		void printOption(Options option, string optionMsg)
		{
			writeln(to!string(int(option)) ~ " - " ~ optionMsg);
		}

		PuppetListener listener = new PuppetListener(driver, loggerTid);

		void addPinMonitor()
		{
			write("Which pin do you want to monitor? (-1 to cancel): ");
			int pinInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &pinInput);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			listener.addPinListener(pin);
			writeln("Monitoring pin ",pin);
		}

		void removePinMonitor()
		{
			write("Which pin do you want to stop monitoring? (-1 to cancel): ");
			int pinInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &pinInput);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			listener.removePinListener(pin);
			writeln("Stopped monitoring pin ",pin);
		}

		void addVarMonitor()
		{
			write("Which var do you want to monitor? (-1 to cancel): ");
			int varInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &varInput);

			if(varInput < 0)
				return;

			ubyte index = to!ubyte(varInput);

			listener.addVarListener!short(index);
			writeln("Monitoring variable ", index);
		}

		void removeVarMonitor()
		{
			write("Which var do you want to stop monitoring? (-1 to cancel): ");
			int varInput = -1;
			string input = readln().chomp();
			formattedRead(input, " %s", &varInput);

			if(varInput < 0)
				return;

			ubyte index = to!ubyte(varInput);

			listener.removeVarListener!short(index);
			writeln("Stopping monitoring variable ", index);
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
				printOption(startPinMonitor, "Monitor analog input");
				printOption(stopPinMonitor, "Stop monitoring analog input");
				printOption(startVarMonitor, "Monitor internal variable");
				printOption(stopVarMonitor, "Stop monitoring internal variable");
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

				case startPinMonitor:
					if(driver.isCommunicationEstablished)
						addPinMonitor();
					else
						printCommunicationRequired();
					break;

				case stopPinMonitor:
					if(driver.isCommunicationEstablished)
						removePinMonitor();
					else
						printCommunicationRequired();
					break;

				case startVarMonitor:
					if(driver.isCommunicationEstablished)
						addVarMonitor();
					else
						printCommunicationRequired();
					break;

				case stopVarMonitor:
					if(driver.isCommunicationEstablished)
						removeVarMonitor();
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

class PuppetListener
{
	Puppeteer driver;
	Tid loggerTid;

	this(Puppeteer driver, Tid loggerTid)
	{
		this.driver = driver;
		this.loggerTid = loggerTid;
	}

	void pinListenerMethod(ubyte pin, float value)
	{
		loggerTid.send(MainMessage(to!string(timer.peek().msecs)~" => Pin "~to!string(pin)~" read "~to!string(value)));
	}

	void varListenerMethod(VarType)(ubyte varIndex, VarType value)
	{
		loggerTid.send(MainMessage(to!string(timer.peek().msecs)~" => Var "~to!string(varIndex)~ " of type " ~ VarType.stringof ~ " read "~to!string(value)));
	}

	void addPinListener(ubyte pin)
	{
		driver.addPinListener(pin, &pinListenerMethod);
	}

	void removePinListener(ubyte pin)
	{
		driver.removePinListener(pin, &pinListenerMethod);
	}

	void addVarListener(VarType)(ubyte varIndex)
	{
		driver.addVariableListener(varIndex, &varListenerMethod!VarType);
	}

	void removeVarListener(VarType)(ubyte varIndex)
	{
		driver.removeVariableListener(varIndex, &varListenerMethod!VarType);
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
