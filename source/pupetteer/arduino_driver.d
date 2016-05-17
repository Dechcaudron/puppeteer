module pupetteer.arduino_driver;

import pupetteer.serial.ISerialPort;
import pupetteer.serial.BaudRate;
import pupetteer.serial.Parity;

import std.concurrency;
import std.conv;

import core.time;

import std.stdio;

protected alias readListenerDelegate = void delegate (ubyte, float) shared;

class ArduinoDriver
{
	private ArduinoCommunicator communicator;

	/**
		Associative array whose key is the pin in which a listener listens, and
		its value a slice of delegates which are the listeners themselves
	*/
	protected shared ListenerHolder[ubyte] listenerHolders;

	this(string filename, Parity parity = Parity.none, BaudRate baudRate = BaudRate.B9600)
	{
		communicator = new ArduinoCommunicator(filename, baudRate, parity, listenerHolders);
	}

	void listen(ubyte pin, readListenerDelegate listener)
	in
	{
		assert(listener !is null);
	}

	body
	{
		if(pin !in listenerHolders)
			listenerHolders[pin] = new shared ListenerHolder(listener);
		else
		{
			synchronized(listenerHolders[pin])
				listenerHolders[pin].add(listener);
		}
	}


	void stopListening(ubyte pin, readListenerDelegate listener)
	in
	{
		assert(listener !is null);
	}

	body
	{
		synchronized(listenerHolders[pin])
			listenerHolders[pin].remove(listener);
	}

	void startCommunication()
	{
		communicator.startCommunication();
	}

	void endCommunication()
	{
		communicator.endCommunication();
	}



}

private class ArduinoCommunicator
{
	private shared ListenerHolder[ubyte] readListeners;

	private string fileName;
	private immutable BaudRate baudRate;
	private immutable Parity parity;

	private Tid workerId;

	this(string fileName, BaudRate baudRate, Parity parity, shared ListenerHolder[ubyte] readListeners)
	{
		this.fileName = fileName;
		this.baudRate = baudRate;
		this.parity = parity;

		this.readListeners = readListeners;
	}

	public void startCommunication()
	{
		workerId = spawn(&communicationLoop, fileName, baudRate, parity);
	}

	public void endCommunication()
	{
		workerId.send(CommunicationMessage(CommunicationMessagePurpose.endCommunication));
	}

	private void communicationLoop(string fileName, immutable BaudRate baudRate, immutable Parity parity) shared
	{
		ISerialPort arduinoSerialPort = ISerialPort.getInstance(fileName, parity, baudRate, 50);

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
				error = 0xff
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
				enum arduinoAnalogReadMax = 1023;

				ubyte pin = command[1];
				ushort readValue = command[2] * ubyte.init + command[3];
				float realValue = to!float(readValue) / arduinoAnalogReadMax;

				synchronized(readListeners[pin])
				{
					foreach(listener; readListeners[pin].getListeners())
					{
						listener(pin, readValue);
					}
				}
			}

			static ubyte[] readBuffer = [];

			readBuffer ~= readBytes;

			//Try to make sense out of the readBytes
			switch(readBuffer[0])
			{
				case ReadCommands.read:
					if(readBuffer.length < 4)
						return;
					else
					{
						handleReadCommand(readBuffer[0..4]);
						readBuffer = readBuffer[4..$];
					}
					break;

				case ReadCommands.error:
					writeln("Error received!");
					break;

				default:
					writeln("Unhandled ubyte command received: ", readBuffer[0]);
			}
		}

		do
		{
			writeln("Looping");
			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

			if(readBytes !is null)
				handleReadBytes(readBytes);

			receiveTimeout(msecs(receiveTimeoutMs), &messageHandler);


		}while(shouldContinue);

		writeln("Ended communicationLoop");
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
}

private class ListenerHolder
{
	private shared readListenerDelegate[] listeners;

	this(readListenerDelegate listener) shared
	{
		listeners ~= listener;
	}

	public void add(readListenerDelegate listener) shared
	{
		listeners ~= listener;
	}

	public void remove(readListenerDelegate listener) shared
	{
		import std.algorithm.mutation;

		listeners = listeners.remove!(a => a is listener);
	}

	public shared(const(readListenerDelegate[])) getListeners() const shared
	{
		return listeners;
	}
}
