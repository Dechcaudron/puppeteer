import std.stdio;
import std.exception;
import std.getopt;
import std.file;
import std.conv;
import std.string;
import std.format;

import dummy_listener;

import puppeteer.puppeteer;

import puppeteer.logging.ipuppeteer_logger;

import puppeteer.communication.communicator;

import puppeteer.configuration.configuration;
import puppeteer.configuration.invalid_configuration_exception;

immutable string loggerTidName = "loggerTid";

void main(string[] args)
{
	scope(exit) writeln("Program finished");

	string devFilename = "";
	string loggingFilename = "puppeteerOut.txt";

	getopt(args,
		"dev|d", &devFilename,
		"out|o", &loggingFilename);

	enforce(devFilename != "" && exists(devFilename), "Please select an existing device using --dev [devicePath]");

	writeln("Opening device file " ~ devFilename);

	shared IPuppeteerLogger logger;

	version(gnuplotCrafterLogging)
	{
		import puppeteer.logging.multifile_gnuplot_crafter_logger;

		logger = new shared MultifileGnuplotCrafterLogger!(5)("gnuplot/");
	}
	else
	{
		import puppeteer.logging.puppeteer_logger;

		logger = new shared PuppeteerLogger(loggingFilename);
	}

	scope auto demoPuppeteer = new shared Puppeteer!short(new shared Communicator!short,
	 							new shared Configuration!short,
								logger);

	scope(exit) destroy(demoPuppeteer);

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
			pwmAvg,
            setAIAdapter,
			setPWMOutAvgAdapter,
            setVarMonitorAdapter,
			setAISensorName,
			setVarMonitorSensorName,
            saveConfig,
            loadConfig,
			exit
		}

		void printOption(Options option, string optionMsg)
		{
			writeln(to!string(int(option)) ~ " - " ~ optionMsg);
		}

		auto listener = new shared DummyListener!short(demoPuppeteer);

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
			demoPuppeteer.setPWM(pin, pwmValue);
		}

		void setPWMAverage()
		{
			write("Introduce pin and PWM average value [pin-avgValue] (-1 to cancel): ");

			int pinInput = -1;
			float pwmValue;
			string input = readln().chomp();
			formattedRead(input, " %s-%s", &pinInput, &pwmValue);

			if(pinInput < 0)
				return;

			ubyte pin = to!ubyte(pinInput);

			writeln("Setting PWM pin ", pin, " to value ", pwmValue);
			demoPuppeteer.setPWMAverage(pin, pwmValue);
		}

        void setAIAdapter()
        {
            write("Analog input adapter [pin:f(x)] (-1 to cancel): ");

            int pinInput = -1;
            string expr;
            string input = readln().chomp();
            formattedRead(input, " %s:%s", &pinInput, &expr);

            if(pinInput < 0)
                return;

            ubyte pin = to!ubyte(pinInput);
            demoPuppeteer.configuration.setAIValueAdapterExpression(pin, expr);

            writefln("Setting AI adapter for pin %s to f(x)=%s", pin, expr !is null ? expr : "x");
        }

		void setPWMOutAvgAdapter()
		{
			write("PWM output average adapter [pin:f(x)] (-1 to cancel): ");

            int pinInput = -1;
            string expr;
            string input = readln().chomp();
            formattedRead(input, " %s:%s", &pinInput, &expr);

            if(pinInput < 0)
                return;

            ubyte pin = to!ubyte(pinInput);
            demoPuppeteer.configuration.setPWMOutAvgAdapterExpression(pin, expr);

            writefln("Setting AI adapter for pin %s to f(x)=%s", pin, expr !is null ? expr : "x");
		}

        void setVarMonitorAdapter()
        {
            write("Internal variable adapter [varIndex:f(x)] (-1 to cancel): ");

            int varIndexInput = -1;
            string expr;
            string input = readln().chomp();
            formattedRead(input, " %s:%s", &varIndexInput, &expr);

            if(varIndexInput < 0)
                return;

            ubyte varIndex = to!ubyte(varIndexInput);
            demoPuppeteer.configuration.setVarMonitorValueAdapterExpression!short(varIndex, expr);

            writefln("Setting variable adapter for internal variable %s to f(x)=%s", varIndex, expr !is null ? expr : "x");
        }

		void setAISensorName()
		{
			write("Analog Input sensor name [pin:name](<empty + Enter> to cancel): ");

			string name;
			int pin;
			string input = readln().chomp();

			if(input.empty)
			{
				writeln("Sensor name setting has been cancelled.");
				return;
			}

			formattedRead(input, " %s:%s", &pin, &name);

			if(name.empty)
			{
				writeln("Reseting sensor name");
				name = null;
			}

			demoPuppeteer.configuration.setAISensorName(to!ubyte(pin), name);
			writefln("AI %s sensor name set to %s", pin, demoPuppeteer.configuration.getAISensorName(to!ubyte(pin)));
		}

		void setVarMonitorSensorName()
		{
			write("Variable Monitor sensor name [index:name](<empty + Enter> to cancel): ");

			string name;
			int index;
			string input = readln().chomp();

			if(input.empty)
			{
				writeln("Sensor name setting has been cancelled.");
				return;
			}

			formattedRead(input, " %s:%s", &index, &name);

			if(name.empty)
			{
				writeln("Reseting sensor name");
				name = null;
			}

			demoPuppeteer.configuration.setVarMonitorSensorName!short(to!ubyte(index), name);
			writefln("Var Monitor %s sensor name set to %s", index, demoPuppeteer.configuration.getVarMonitorSensorName!short(to!ubyte(index)));
		}

        void saveConfigUI()
        {
            write("Path of the file to save the puppeteer configuration in (<empty + Enter> to cancel): ");

            string filename;
            string input = readln().chomp();
            formattedRead(input, " %s", &filename);

            if(filename == "")
            {
                writeln("Configuration saving has been cancelled.");
                return;
            }

            bool failedToWrite = false;
            try
            {
                File f = File(filename, "w");
                demoPuppeteer.configuration.save(f);
                writefln("Configuration saved to %s.", filename);
            }
            catch(Exception e)
            {
                debug writeln(e);
                failedToWrite = true;
            }

            if(failedToWrite)
                writefln("Could not save configuration to %s.", filename);
        }

        void loadConfigUI()
        {
            write("Path of the file to load the puppeteer configuration from (<empty + Enter> to cancel): ");

            string filename;
            string input = readln().chomp();
            formattedRead(input, " %s", &filename);

            if(filename == "")
            {
                writeln("Configutation loading has been cancelled.");
                return;
            }

            bool failedToRead = false;

            try
            {
                File f = File(filename, "r");
                demoPuppeteer.configuration.load(f);
                writefln("Loaded configuration from file %s into the puppeteer.", filename);
            }
            catch(InvalidConfigurationException e)
            {
                debug writeln(e);
                writefln("The configuration from %s is not valid for this puppeteer.", filename);
            }
            catch(Exception e)
            {
                debug writeln(e);
                failedToRead = true;
            }

            if(failedToRead)
                writefln("Could not load configuration from %s.", filename);
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
				printOption(pwmAvg, "Set PWM average output");
                printOption(setAIAdapter, "Set AI value adapter");
				printOption(setPWMOutAvgAdapter, "Set PWM out average adapter");
                printOption(setVarMonitorAdapter, "Set internal variable value adapter");
				printOption(setAISensorName, "Set AI sensor name");
				printOption(setVarMonitorSensorName, "Set Variable Monitor sensor name");
                printOption(saveConfig, "Save puppeteer configuration");
                printOption(loadConfig, "Load puppeteer configuration");
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


			try
			{
				final switch(to!Options(option))
				{
					case Options.start:
						if(!demoPuppeteer.isCommunicationEstablished)
						{
							writeln("Establishing communication with puppet...");
							if(demoPuppeteer.startCommunication(devFilename, BaudRate.B9600, Parity.none, loggingFilename))
							{
								writeln("Communication established.");
							}
							else
								writeln("Could not establish communication with puppet.");
						}
						else
							writeln("Communication is already established.");

						break;

					case Options.stop:
						if(demoPuppeteer.isCommunicationEstablished)
						{
							demoPuppeteer.endCommunication();
							writeln("Communication ended.");
						}
						else
							writeln("Communication has not been established yet.");
						break;

					case Options.startPinMonitor:
						if(demoPuppeteer.isCommunicationEstablished)
							addPinMonitor();
						else
							printCommunicationRequired();
						break;

					case Options.stopPinMonitor:
						if(demoPuppeteer.isCommunicationEstablished)
							removePinMonitor();
						else
							printCommunicationRequired();
						break;

					case Options.startVarMonitor:
						if(demoPuppeteer.isCommunicationEstablished)
							addVarMonitor();
						else
							printCommunicationRequired();
						break;

					case Options.stopVarMonitor:
						if(demoPuppeteer.isCommunicationEstablished)
							removeVarMonitor();
						else
							printCommunicationRequired();
						break;

					case Options.pwm:
						if(demoPuppeteer.isCommunicationEstablished)
							setPWM();
						else
							printCommunicationRequired();
						break;

					case Options.pwmAvg:
						if(demoPuppeteer.isCommunicationEstablished)
							setPWMAverage();
						else
							printCommunicationRequired();
						break;

	                case Options.setAIAdapter:
	                    setAIAdapter();
	                    break;

					case Options.setPWMOutAvgAdapter:
						setPWMOutAvgAdapter();
						break;

	                case Options.setVarMonitorAdapter:
	                    setVarMonitorAdapter();
	                    break;

					case Options.setAISensorName:
						setAISensorName();
						break;

					case Options.setVarMonitorSensorName:
						setVarMonitorSensorName();
						break;

	                case Options.saveConfig:
	                    saveConfigUI();
	                    break;

	                case Options.loadConfig:
	                    loadConfigUI();
	                    break;

					case Options.exit:
						if(demoPuppeteer.isCommunicationEstablished)
						{
							writeln("Finishing communication with puppet...");
							demoPuppeteer.endCommunication();
						}
						break menu;
				}
			}
			catch(ConvException e)
			{
				debug writeln(e);
				writeln("Please select a valid option");
			}
		}
	}

	showMenu();
}
