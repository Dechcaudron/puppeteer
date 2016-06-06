module puppeteer.arduino_driver;

import puppeteer.serial.ISerialPort;
import puppeteer.serial.BaudRate;
import puppeteer.serial.Parity;

import puppeteer.internal.listener_holder;

import std.concurrency;
import std.conv;
import std.typecons;
import std.exception;

import core.time;
import core.thread;

import std.stdio;

public alias readListenerDelegate = void delegate (ubyte, float);

class ArduinoDriver
{
	protected shared ListenerHolder[ubyte] listenerHolders;

	protected shared bool communicationOn;

	string filename;
	immutable Parity parity;
	immutable BaudRate baudRate;

	private Tid workerId;

	this(string filename, Parity parity = Parity.none, BaudRate baudRate = BaudRate.B9600)
	{
		this.filename = filename;
		this.parity = parity;
		this.baudRate = baudRate;
	}

	void addListener(ubyte pin, readListenerDelegate listener)
	in
	{
		assert(listener !is null);
		assert(communicationOn);
	}
	body
	{
		if(pin !in listenerHolders)
		{
			listenerHolders[pin] = new shared ListenerHolder(listener);

			writeln("Sending message to dynamically enable monitoring of pin "~to!string(pin));
			workerId.send(CommunicationMessage(CommunicationMessagePurpose.startMonitoring, pin));
		}
		else
		{
			synchronized(listenerHolders[pin])
			{
				listenerHolders[pin].add(listener);
			}
		}
	}


	void removeListener(ubyte pin, readListenerDelegate listener)
	in
	{
		assert(listener !is null);
		assert(communicationOn);
		assert(pin in listenerHolders);
	}
	body
	{
		synchronized(listenerHolders[pin])
		{
			listenerHolders[pin].remove(listener);

			/*If there are no remaining listeners for that pin,
			remove the holder and command the puppet to stop monitoring
			the specified pin*/
			if(listenerHolders[pin].getListenersNumber == 0)
			{
				listenerHolders.remove(pin);
				workerId.send(CommunicationMessage(CommunicationMessagePurpose.stopMonitoring, pin));
			}
		}
	}

	void setPWM(ubyte pin, ubyte value)
	in
	{
		assert(communicationOn);
		assert(workerId != Tid.init);
	}
	body
	{
		workerId.send(CommunicationMessage(CommunicationMessagePurpose.setPWM, pin, value));
	}

	bool startCommunication()
	in
	{
		assert(!communicationOn);
	}
	body
	{
		workerId = spawn(&communicationLoop, filename, baudRate, parity);

		auto msg = receiveOnly!CommunicationEstablishedMessage();
		return msg.success;
	}

	void endCommunication()
	in
	{
		assert(communicationOn);
	}
	body
	{
		workerId.send(CommunicationMessage(CommunicationMessagePurpose.endCommunication));

		receiveOnly!CommunicationEndedMessage();
	}

	@property
	bool isCommunicationEstablished()
	{
		return communicationOn;
	}

	private void communicationLoop(string fileName, immutable BaudRate baudRate, immutable Parity parity) shared
	{
		enum receiveTimeoutMs = 10;
		enum bytesReadAtOnce = 1;

		enum ubyte commandControlByte = 0xff;

		bool shouldContinue = true;

		ISerialPort arduinoSerialPort;

		void sendStartMonitoringCommand(ISerialPort serialPort, ubyte pin)
		{
			writeln("Sending startMonitoringCommand for pin "~to!string(pin));
			serialPort.write([commandControlByte, 0x01, pin]);
		}

		void sendStopMonitoringCommand(ISerialPort serialPort, ubyte pin)
		{
      		writeln("Sending stopMonitoringCommand for pin "~to!string(pin));
			serialPort.write([commandControlByte, 0x02, pin]);
		}

		void sendSetPWMCommand(ISerialPort serialPort, ubyte pin, ubyte value)
		{
			writeln("Sending setPWMCommand for pin "~to!string(pin)~" and value "~to!string(value));
			serialPort.write([commandControlByte, 0x04, pin, value]);
		}

		void handleMessage(CommunicationMessage message)
		{
			with(CommunicationMessagePurpose)
			{
				switch(message.purpose)
				{
					case endCommunication:
						shouldContinue = false;
						break;

                    case startMonitoring:
                        sendStartMonitoringCommand(arduinoSerialPort, message.pin);
                        break;

					case stopMonitoring:
						sendStopMonitoringCommand(arduinoSerialPort, message.pin);
						break;

					case setPWM:
						sendSetPWMCommand(arduinoSerialPort, message.pin, message.value);
						break;

					default:
						writeln("Unhandled message purpose "~to!string(message.purpose)~" received");
				}
			}
		}

		void handleReadBytes(ubyte[] readBytes)
		in
		{
			assert(readBytes !is null);
			assert(readBytes.length != 0);
		}
		body
		{
			enum ReadCommands : ubyte
			{
				read = 0x1,
				error = 0xfe
			}

			void handleReadCommand(ubyte[] command)
			in
			{
				assert(command !is null);
				assert(command.length == 4);
				assert(command[0] == ReadCommands.read);
			}
			body
			{
				writeln("Handling readCommand ", command);

				ubyte pin = command[1];

				if(pin in listenerHolders)
				{
					enum arduinoAnalogReadMax = 1023;
					enum arduinoAnalogReference = 5;
					enum ubytePossibleValues = 256;

					ushort readValue = command[2] * ubytePossibleValues + command[3];
					float realValue =  arduinoAnalogReference * to!float(readValue) / arduinoAnalogReadMax;

					synchronized(listenerHolders[pin])
					{
						foreach(listener; listenerHolders[pin].getListeners())
						{
							listener(pin, realValue);
						}
					}
				}else
				{
					//writeln("No listeners registered for pin ",pin);
				}
			}

			static ubyte[] readBuffer = [];

			readBuffer ~= readBytes;

			void popReadBuffer(size_t elements = 1)
			{
				readBuffer = readBuffer.length >= elements ? readBuffer[elements..$] : [];
			}

			if(readBuffer[0] != commandControlByte)
			{
				writeln("Received corrupt command. Discarding first byte and returning");
				popReadBuffer();
				return;
			}

			if(readBuffer.length < 2)
				return;

			//Try to make sense out of the readBytes
			switch(readBuffer[1])
			{
				case ReadCommands.read:
					if(readBuffer.length < 5)
						return;

					handleReadCommand(readBuffer[1..5]);
					popReadBuffer(5);
					break;

				case ReadCommands.error:
					writeln("Error received!");
					break;

				default:
					writeln("Unhandled ubyte command received: ", readBuffer[0], ". Cleaning command buffer.");
					readBuffer = [];
			}
		}

		enum portReadTimeoutMs = 200;
		arduinoSerialPort = ISerialPort.getInstance(fileName, parity, baudRate, portReadTimeoutMs);
		if(!arduinoSerialPort.open())
		{
			ownerTid.send(CommunicationEstablishedMessage(false));
			return;
		}

		communicationOn = true;

		//Arduino seems to need some time between port opening and communication start
		Thread.sleep(dur!"seconds"(1));

		enum ubyte[] puppeteerReadyCommand = [0x0, 0x0];
		arduinoSerialPort.write([commandControlByte] ~ puppeteerReadyCommand);

		//Wait for the puppet to answer it is ready
		{
			enum ubyte[] puppetReadyCommand = [0x0, 0x0];
			ubyte[] cache = [];
			enum msBetweenChecks = 100;

			int readCounter = 0;
			enum readsUntilFailure = 20;

			while(true)
			{
				ubyte[] readBytes = arduinoSerialPort.read(1);

				if(readBytes !is null)
				{
					cache ~= readBytes;
					writeln("cache is currently ", cache);

					if(cache.length == 3)
					{
						if(cache == [commandControlByte] ~ puppetReadyCommand)
							break; //Ready!
						else
							cache = cache[1..$]; //pop front and continue
					}
				}

				if(++readCounter > readsUntilFailure)
				{
					ownerTid.send(CommunicationEstablishedMessage(false));
					return;
				}

				Thread.sleep(dur!"msecs"(msBetweenChecks));
			}
		}

		ownerTid.send(CommunicationEstablishedMessage(true));

		//Send startMonitoringCommands for already present listeners
		foreach(pin; listenerHolders.byKey)
		{
			sendStartMonitoringCommand(arduinoSerialPort, pin);
		}

		do
		{
			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

			if(readBytes !is null)
			{
				//writeln("Read bytes ", readBytes);
				handleReadBytes(readBytes);
			}

			receiveTimeout(msecs(receiveTimeoutMs), &handleMessage);


		}while(shouldContinue);

		communicationOn = false;
		arduinoSerialPort.close();

		ownerTid.send(CommunicationEndedMessage());
	}

	private struct CommunicationEstablishedMessage
	{
		bool success;

		this(bool success)
		{
			this.success = success;
		}
	}

	private struct CommunicationEndedMessage
	{

	}
}


private struct CommunicationMessage
{
	CommunicationMessagePurpose purpose;
	ubyte pin;
	ubyte value;

	this(CommunicationMessagePurpose purpose)
	in
	{
		assert(purpose == CommunicationMessagePurpose.endCommunication);
	}
	body
	{
		this.purpose = purpose;
	}

	this(CommunicationMessagePurpose purpose, ubyte pin)
	in
	{
		assert(purpose != CommunicationMessagePurpose.setPWM);
	}
	body
	{
		this.purpose = purpose;
		this.pin = pin;
	}

	this(CommunicationMessagePurpose purpose, ubyte pin, ubyte value)
	in
	{
		assert(purpose == CommunicationMessagePurpose.setPWM);
	}
	body
	{
		this.purpose = purpose;
		this.pin = pin;
		this.value = value;
	}
}

private enum CommunicationMessagePurpose
{
	endCommunication,
	startMonitoring,
	stopMonitoring,
	read,
	setPWM,
}
