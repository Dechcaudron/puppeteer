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

		bool shouldContinue = true;

		void messageHandler(CommunicationMessage message)
		{
			with(CommunicationMessagePurpose)
			{
				if(message.purpose == endCommunication)
					shouldContinue = false;
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

			enum ubyte commandBeginByte = 0xff;

			if(readBuffer[0] != commandBeginByte)
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
			import core.thread;
			Thread.sleep(core.time.dur!("seconds")(1));
		}

		do
		{
			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

			if(readBytes !is null)
			{
				writeln("Read bytes ", readBytes);
				handleReadBytes(readBytes);
			}

			receiveTimeout(msecs(receiveTimeoutMs), &messageHandler);


		}while(shouldContinue);

		arduinoSerialPort.close();

		communicationOn = false;

		writeln("Ended communicationLoop");
	}
}


private struct CommunicationMessage
{
	CommunicationMessagePurpose purpose;

	this(CommunicationMessagePurpose purpose)
	{
		this.purpose = purpose;
	}
}

private enum CommunicationMessagePurpose
{
	endCommunication,
	read,
	write
}
