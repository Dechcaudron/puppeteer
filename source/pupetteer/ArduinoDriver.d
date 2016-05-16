module pupetteer.arduino_driver;

import pupetteer.serial.ISerialPort;
import pupetteer.serial.BaudRate;
import pupetteer.serial.Parity;

import std.concurrency;

import core.time;

protected alias readListenerDelegate = void delegate (int, float);

class ArduinoDriver
{
	private ArduinoCommunicator communicator;

	/**
		Associative array whose key is the pin in which a listener listens, and
		its value a slice of delegates which are the listeners themselves
	*/
	protected shared ListenerHolder[int] listenerHolders;

	this(string filename, Parity parity = Parity.none, BaudRate baudRate = BaudRate.B9600)
	{
		communicator = new ArduinoCommunicator(filename, baudRate, parity, listenerHolders);
	}

	void listen(int pin, readListenerDelegate listener)
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


	void stopListening(int pin, readListenerDelegate listener)
	in
	{
		assert(listener !is null);
	}

	body
	{
		synchronized(listenerHolders[pin])
			listenerHolders[pin].remove(listener);
	}




}

private class ArduinoCommunicator
{
	private shared ListenerHolder[int] readListeners;

	private string fileName;
	private immutable BaudRate baudRate;
	private immutable Parity parity;

	private Tid workerId;

	this(string fileName, BaudRate baudRate, Parity parity, shared ListenerHolder[int] readListeners)
	{
		this.fileName = fileName;
		this.baudRate = baudRate;
		this.parity = parity;

		this.readListeners = readListeners;
	}

	public void startCommunication()
	{
		spawn(&communicationLoop, fileName, baudRate, parity);
	}

	private void communicationLoop(string fileName, immutable BaudRate baudRate, immutable Parity parity) shared
	{
		ISerialPort arduinoSerialPort = ISerialPort.getInstance(fileName, parity, baudRate, 50);

		enum receiveTimeoutMs = 50;
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

		void handleReadBytes(byte[] readBytes)
		{
			static byte[] readBuffer = [];
		}

		do
		{
			receiveTimeout(msecs(receiveTimeoutMs), &messageHandler);

			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);



		}while(shouldContinue);
	}

	private class CommunicationMessage
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
}
