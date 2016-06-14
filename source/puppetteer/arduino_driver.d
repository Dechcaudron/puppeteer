module puppeteer.arduino_driver;

import puppeteer.serial.ISerialPort;
import puppeteer.serial.BaudRate;
import puppeteer.serial.Parity;

import puppeteer.internal.signal_wrapper;

import std.concurrency;
import std.conv;
import std.typecons;
import std.exception;
import std.signals;
import std.meta;

import core.time;
import core.thread;

import std.stdio;

public alias pinListenerDelegate = void delegate (ubyte, float);

private alias hack(alias a) = a;

class ArduinoDriver(VarMonitorTypes...)
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
	alias PinSignalWrapper = SignalWrapper!(ubyte, float);

	//Manually synchronized between both logical threads
	protected __gshared PinSignalWrapper[ubyte] pinSignalWrappers;
	protected __gshared mixin(unrollVariableSignalWrappers!VarMonitorTypes());

	enum canMonitor(T) = __traits(compiles, mixin(varMonitorSignalWrappersName!T));

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

	void addPinListener(ubyte pin, pinListenerDelegate listener)
	in
	{
		assert(listener !is null);
	}
	body
	{
		enforce(communicationOn);

		if(pin !in pinSignalWrappers)
		{
			PinSignalWrapper signalWrapper = new PinSignalWrapper;

			pinSignalWrappers[pin] = signalWrapper;

			//No need to synchronize this call since it is the first listener
			signalWrapper.addListener(listener);

			writeln("Sending message to dynamically enable monitoring of pin "~to!string(pin));
			workerId.send(CommunicationMessage(CommunicationMessagePurpose.startMonitoring, pin));
		}
		else
		{
			PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

			synchronized(signalWrapper)
			{
				signalWrapper.addListener(listener);
			}
		}
	}


	void removePinListener(ubyte pin, pinListenerDelegate listener)
	in
	{
		assert(listener !is null);
	}
	body
	{
		enforce(communicationOn);
		enforce(pin in pinSignalWrappers);

		PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

		synchronized(signalWrapper)
			signalWrapper.removeListener(listener);

		/*If there are no remaining listeners for that pin,
		remove the holder and command the puppet to stop monitoring
		the specified pin*/
		if(signalWrapper.listenersNumber == 0)
		{
			pinSignalWrappers.remove(pin);
			workerId.send(CommunicationMessage(CommunicationMessagePurpose.stopMonitoring, pin));
		}
	}

	void addVariableListener(MonitorType)(ubyte varIndex, void delegate(ubyte, MonitorType) listener)
	if(canMonitor!MonitorType)
	{
		enforce(communicationOn);
		alias typeSignalWrappers = hack!(mixin(varMonitorSignalWrappersName!MonitorType));

		if(varIndex in typeSignalWrappers)
		{
			auto signalWrapper = typeSignalWrappers[varIndex];

			synchronized(signalWrapper)
			{
				signalWrapper.addListener(listener);
			}
		}
		else
		{
			auto wrapper = new SignalWrapper!(ubyte, MonitorType);
			wrapper.addListener(listener);
			typeSignalWrappers[varIndex] = wrapper;

			workerId.send(VarMonitorMessage(VarMonitorMessage.Action.start, varIndex, VarMonitorTypeCodeName!MonitorType));
		}
	}

	void removeVariableListener(MonitorType)(ubyte varIndex, void delegate(ubyte, MonitorType) listener)
	if(canMonitor!MonitorType)
	{
		enforce(communicationOn);
		alias typeSignalWrappers = hack!(mixin(varMonitorSignalWrappersName!MonitorType));

		enforce(varIndex in typeSignalWrappers);

		auto signalWrapper = typeSignalWrappers[varIndex];

		synchronized(signalWrapper)
			signalWrapper.remove(varIndex);

		if(signalWrapper.listenersNumber == 0)
		{
			typeSignalWrappers.remove(signalWrapper);
			workerId.send(VarMonitorMessage(VarMonitorMessage.Action.stop, varIndex, VarMonitorTypeCodeName!MonitorType));
		}
	}

	void setPWM(ubyte pin, ubyte value)
	in
	{
		assert(workerId != Tid.init);
	}
	body
	{
		enforce(communicationOn);
		workerId.send(CommunicationMessage(CommunicationMessagePurpose.setPWM, pin, value));
	}

	bool startCommunication()
	{
		enforce(!communicationOn);

		workerId = spawn(&communicationLoop, filename, baudRate, parity);

		auto msg = receiveOnly!CommunicationEstablishedMessage();
		return msg.success;
	}

	void endCommunication()
	{
		enforce(communicationOn);

		workerId.send(CommunicationMessage(CommunicationMessagePurpose.endCommunication));

		//Remove all listeners
		foreach(pin; pinSignalWrappers.byKey())
		{
			synchronized(pinSignalWrappers[pin])
				pinSignalWrappers.remove(pin);
		}

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

		void sendPuppeteerClosedCommand(ISerialPort serialPort)
		{
			writeln("Sending puppeteerClosedCommand");
			serialPort.write([commandControlByte, 0x99]);
		}

		void sendStartMonitoringVariableCmd(ISerialPort serialPort, VarMonitorTypeCode typeCode, byte varIndex)
		{
			writeln("Sending startMonitoringVariableCommand for type ", typeCode, "and index ", varIndex);
			serialPort.write([commandControlByte, 0x05, typeCode, varIndex]);
		}

		void sendStopMonitoringVariableCmd(ISerialPort serialPort, VarMonitorTypeCode typeCode, byte varIndex)
		{
			writeln("Sending stopMonitoringVariableCommand for type ", typeCode, "and index ", varIndex);
			serialPort.write([commandControlByte, 0x06, typeCode, varIndex]);
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
						writeln("Unhandled message purpose ", message.purpose, " received");
				}
			}
		}

		void handleVarMonitorMessage(VarMonitorMessage message)
		{
			message.action == VarMonitorMessage.Action.start ? sendStartMonitoringVariableCmd(arduinoSerialPort, message.varTypeCode, message.varIndex) :
																sendStopMonitoringVariableCmd(arduinoSerialPort, message.varTypeCode, message.varIndex);
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
				analogMonitor = 0x1,
				varMonitor = 0x2,
				error = 0xfe
			}

			void handleAnalogMonitorCommand(ubyte[] command)
			in
			{
				assert(command !is null);
				assert(command.length == 4);
				assert(command[0] == ReadCommands.analogMonitor);
			}
			body
			{
				writeln("Handling analogMonitorCommand ", command);

				ubyte pin = command[1];

				if(pin in pinSignalWrappers)
				{
					enum arduinoAnalogReadMax = 1023;
					enum arduinoAnalogReference = 5;
					enum ubytePossibleValues = 256;

					ushort readValue = command[2] * ubytePossibleValues + command[3];
					float realValue =  arduinoAnalogReference * to!float(readValue) / arduinoAnalogReadMax;

					PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

					synchronized(signalWrapper)
					{
						signalWrapper.emit(pin, realValue);
					}

				}else
				{
					writeln("No listeners registered for pin ",pin);
				}
			}

			void handleVarMonitorCommand(ubyte[] command)
			in
			{
				assert(command !is null);
				assert(command.length == 4);
				assert(command[0] == ReadCommands.varMonitor;)
			}
			body
			{
				writeln("Handling varMonitorCommand");

				void handleData(ubyte[] data)(VarType)
				{

				}

				void delegate (ubyte[]) selectDelegate(ubyte typeCode)
				{
					switch(typeCode) with (VarMonitorTypeCode)
					{
						case int_t:
							return handleData!int;

						case float_t:
							return handleData!float;
							break;

						default:
							writeln("No delegate for varMonitorType of code ",type);
							return null;
					}
				}

				auto del = selectDelegate(command[1]);

				if(del !is null)
					del(command[2..$]);
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
				case ReadCommands.analogMonitor:
					if(readBuffer.length < 5)
						return;

					handleAnalogMonitorCommand(readBuffer[1..5]);
					popReadBuffer(5);
					break;

				case ReadCommands.varMonitor:
					if(readBuffer.length < 5)
						return;

					handleVarMonitorCommand(readBuffer[1..5]);
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
			enum readsUntilFailure = 30;

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

		communicationOn = true;
		ownerTid.send(CommunicationEstablishedMessage(true));

		do
		{
			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

			if(readBytes !is null)
			{
				//writeln("Read bytes ", readBytes);
				handleReadBytes(readBytes);
			}

			receiveTimeout(msecs(receiveTimeoutMs), &handleMessage, &handleVarMonitorMessage);

		}while(shouldContinue);

		sendPuppeteerClosedCommand(arduinoSerialPort);

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

	private struct VarMonitorMessage
	{
		enum Action
		{
			start,
			stop
		}

		private Action action;
		private ubyte varIndex;
		private VarMonitorTypeCode varTypeCode;

		this(Action action, ubyte varIndex, VarMonitorTypeCode varTypeCode)
		{
			this.action = action;
			this.varIndex = varIndex;
			this.varTypeCode = varTypeCode;
		}
	}
}
unittest
{
	assert(__traits(compiles, ArduinoDriver!int));
	assert(__traits(compiles, ArduinoDriver!float));
	assert(__traits(compiles, ArduinoDriver!(int, float)));
	assert(!__traits(compiles, ArduinoDriver!(int, void)));
}

private enum VarMonitorTypeCode : byte
{
	int_t = 0x0,
	float_t = 0x01
}

enum isVarMonitorTypeSupported(VarType) = __traits(compiles, VarMonitorTypeCodeName!VarType);
unittest
{
	assert(isVarMonitorTypeSupported!int);
	assert(isVarMonitorTypeSupported!float);
	assert(!isVarMonitorTypeSupported!void);
}

template VarMonitorTypeCodeName(VarType)
{
	alias VarMonitorTypeCodeName = hack!(mixin(VarMonitorTypeCode.stringof ~ "." ~ VarType.stringof ~ "_t"));
}
unittest
{
	assert(VarMonitorTypeCodeName!int == VarMonitorTypeCode.int_t);
	assert(VarMonitorTypeCodeName!float == VarMonitorTypeCode.float_t);
}

//TODO: split into multiple messages, this struct is horrible
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

private string unrollVariableSignalWrappers(VarTypes...)()
{
	string unroll = "";

	foreach(varType; VarTypes)
	{
		unroll ~= varMonitorSignalWrappersType!varType ~ " " ~ varMonitorSignalWrappersName!varType ~ ";\n";
	}

	return unroll;
}


enum varMonitorSignalWrappersType(VarType) = "SignalWrapper!(ubyte, " ~ VarType.stringof ~ ")[ubyte]";
unittest
{
	assert(varMonitorSignalWrappersType!int == "SignalWrapper!(ubyte, int)[ubyte]");
	assert(varMonitorSignalWrappersType!float == "SignalWrapper!(ubyte, float)[ubyte]");
	assert(varMonitorSignalWrappersType!byte == "SignalWrapper!(ubyte, byte)[ubyte]");
}


enum varMonitorSignalWrappersName(VarType) = VarType.stringof ~ "SignalWrappers";
unittest
{
	assert(varMonitorSignalWrappersName!int == "intSignalWrappers");
}
