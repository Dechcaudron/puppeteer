module pupetteer.arduino_driver;

import pupetteer.serial.ISerialPort;
import pupetteer.serial.BaudRate;
import pupetteer.serial.Parity;

import pupetteer.internal.listener_holder;

import std.concurrency;
import std.conv;

import core.time;

import std.stdio;

public alias readListenerDelegate = void delegate (ubyte, float) shared;

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
	}
	body
	{
		if(pin !in listenerHolders)
		{
			listenerHolders[pin] = new shared ListenerHolder(listener);

			if(communicationOn)
			{
				workerId.send(CommunicationMessage(CommunicationMessagePurpose.startMonitoring, pin));
			}

		}else
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

	void startCommunication()
	{
		workerId = spawn(&communicationLoop, filename, baudRate, parity);
	}

	void endCommunication()
	{
		workerId.send(CommunicationMessage(CommunicationMessagePurpose.endCommunication));
	}

	private void communicationLoop(string fileName, immutable BaudRate baudRate, immutable Parity parity) shared
	{
		enum receiveTimeoutMs = 10;
		enum bytesReadAtOnce = 1;

		enum ubyte commandControlByte = 0xff;

		bool shouldContinue = true;

		void handleMessage(CommunicationMessage message)
		{
			with(CommunicationMessagePurpose)
			{
				switch(message.purpose)
				{
					case endCommunication:
						shouldContinue = false;
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
					writeln("No listeners registered for pin ",pin);
				}
			}

			static ubyte[] readBuffer = [];

			readBuffer ~= readBytes;

			if(readBuffer[0] != commandControlByte)
			{
				writeln("Received corrupt command. Discarding first byte and returning");
				readBuffer = readBuffer.length != 1? readBuffer[1..$] : [];
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
					else
					{
						handleReadCommand(readBuffer[1..5]);
						readBuffer = readBuffer[5..$];
					}
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
		ISerialPort arduinoSerialPort = ISerialPort.getInstance(fileName, parity, baudRate, portReadTimeoutMs);
		arduinoSerialPort.open();
		communicationOn = true;

		{
			//Arduino seems to need some time between port opening and communication start
			import core.thread;
			Thread.sleep(core.time.dur!("seconds")(1));
		}

		void sendStartMonitoringCommand(ubyte pin)
		{
			writeln("Sending startMonitoringCommand for pin "~pin);
			arduinoSerialPort.write([commandControlByte, 0x01, pin]);
		}

		void sendStopMonitoringCommand(ubyte pin)
		{
			writeln("Sending stopMonitoringCommand for pin "~pin);
			arduinoSerialPort.write([commandControlByte, 0x02, pin]);
		}

		//Send startMonitoringCommands for already present listeners
		foreach(pin; listenerHolders.byKey)
		{
			sendStartMonitoringCommand(pin);
		}

		do
		{
			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

			if(readBytes !is null)
			{
				writeln("Read bytes ", readBytes);
				handleReadBytes(readBytes);
			}

			receiveTimeout(msecs(receiveTimeoutMs), &handleMessage);


		}while(shouldContinue);

		communicationOn = false;
		arduinoSerialPort.close();

		writeln("Ended communicationLoop");
	}
}


private struct CommunicationMessage
{
	CommunicationMessagePurpose purpose;
	ubyte pin;

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
		assert(purpose != CommunicationMessagePurpose.write);
	}
	body
	{
		this.purpose = purpose;
	}
}

private enum CommunicationMessagePurpose
{
	endCommunication,
	startMonitoring,
	stopMonitoring,
	read,
	write
}
