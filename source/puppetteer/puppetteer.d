module puppeteer.puppeteer;

import puppeteer.serial.ISerialPort;
import puppeteer.serial.BaudRate;
import puppeteer.serial.Parity;

import puppeteer.signal_wrapper;

import std.stdio;
import std.concurrency;
import std.conv;
import std.typecons;
import std.exception;
import std.signals;
import std.meta;
import std.datetime;

import core.time;
import core.thread;


public alias pinListenerDelegate = void delegate (ubyte, float, long) shared;

private alias hack(alias a) = a;

class Puppetteer(VarMonitorTypes...)
if(allSatisfy!(isVarMonitorTypeSupported, VarMonitorTypes))
{
	alias PinSignalWrapper = SignalWrapper!(ubyte, float, long);

	//Manually synchronized between both logical threads
	protected shared PinSignalWrapper[ubyte] pinSignalWrappers;
	protected shared mixin(unrollVariableSignalWrappers!VarMonitorTypes());

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
			shared PinSignalWrapper signalWrapper = new PinSignalWrapper;

			pinSignalWrappers[pin] = signalWrapper;

			//No need to synchronize this call since it is the first listener
			signalWrapper.addListener(listener);

			writeln("Sending message to dynamically enable monitoring of pin "~to!string(pin));
			workerId.send(PinMonitorMessage(PinMonitorMessage.Action.start, pin));
		}
		else
		{
			shared PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

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

		shared PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

		synchronized(signalWrapper)
			signalWrapper.removeListener(listener);

		if(signalWrapper.listenersNumber == 0)
		{
			pinSignalWrappers.remove(pin);
			workerId.send(PinMonitorMessage(PinMonitorMessage.Action.stop, pin));
		}
	}

	void addVariableListener(MonitorType)(ubyte varIndex, void delegate(ubyte, MonitorType, long) shared listener)
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
			auto wrapper = new shared SignalWrapper!(ubyte, MonitorType, long);
			wrapper.addListener(listener);
			typeSignalWrappers[varIndex] = wrapper;

			workerId.send(VarMonitorMessage(VarMonitorMessage.Action.start, varIndex, varMonitorTypeCode!MonitorType));
		}
	}

	void removeVariableListener(MonitorType)(ubyte varIndex, void delegate(ubyte, MonitorType, long) shared listener)
	if(canMonitor!MonitorType)
	{
		enforce(communicationOn);
		alias typeSignalWrappers = hack!(mixin(varMonitorSignalWrappersName!MonitorType));

		enforce(varIndex in typeSignalWrappers);

		auto signalWrapper = typeSignalWrappers[varIndex];

		synchronized(signalWrapper)
			signalWrapper.removeListener(listener);

		if(signalWrapper.listenersNumber == 0)
		{
			typeSignalWrappers.remove(varIndex);
			workerId.send(VarMonitorMessage(VarMonitorMessage.Action.stop, varIndex, varMonitorTypeCode!MonitorType));
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
		workerId.send(SetPWMMessage(pin, value));
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

		workerId.send(EndCommunicationMessage());

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

		void sendStartMonitoringPinCmd(ISerialPort serialPort, ubyte pin)
		{
			writeln("Sending startMonitoringCommand for pin "~to!string(pin));
			serialPort.write([commandControlByte, 0x01, pin]);
		}

		void sendStopMonitoringPinCmd(ISerialPort serialPort, ubyte pin)
		{
      		writeln("Sending stopMonitoringCommand for pin "~to!string(pin));
			serialPort.write([commandControlByte, 0x02, pin]);
		}

		void sendSetPWMCmd(ISerialPort serialPort, ubyte pin, ubyte value)
		{
			writeln("Sending setPWMCommand for pin "~to!string(pin)~" and value "~to!string(value));
			serialPort.write([commandControlByte, 0x04, pin, value]);
		}

		void sendStartMonitoringVariableCmd(ISerialPort serialPort, VarMonitorTypeCode typeCode, byte varIndex)
		{
			writeln("Sending startMonitoringVariableCommand for type ", typeCode, " and index ", varIndex);
			serialPort.write([commandControlByte, 0x05, typeCode, varIndex]);
		}

		void sendStopMonitoringVariableCmd(ISerialPort serialPort, VarMonitorTypeCode typeCode, byte varIndex)
		{
			writeln("Sending stopMonitoringVariableCommand for type ", typeCode, " and index ", varIndex);
			serialPort.write([commandControlByte, 0x06, typeCode, varIndex]);
		}

        void handlePinMonitorMessage(PinMonitorMessage msg)
        {
            final switch(msg.action) with (PinMonitorMessage.Action)
            {
                case start:
                    sendStartMonitoringPinCmd(arduinoSerialPort, msg.pin);
                    break;

                case stop:
                    sendStopMonitoringPinCmd(arduinoSerialPort, msg.pin);
                    break;
            }
        }

        void handleEndCommunicationMessage(EndCommunicationMessage msg)
        {
            shouldContinue = false;
        }

		void handleVarMonitorMessage(VarMonitorMessage msg)
		{
            final switch(msg.action) with (VarMonitorMessage.Action)
            {
                case start:
                    sendStartMonitoringVariableCmd(arduinoSerialPort, msg.varTypeCode, msg.varIndex);
                    break;

                case stop:
                    sendStopMonitoringVariableCmd(arduinoSerialPort, msg.varTypeCode, msg.varIndex);
                    break;
            }
		}

        void handleSetPWMMessage(SetPWMMessage msg)
        {
            sendSetPWMCmd(arduinoSerialPort, msg.pin, msg.value);
        }

		StopWatch timer;

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

					shared PinSignalWrapper signalWrapper = pinSignalWrappers[pin];

					synchronized(signalWrapper)
					{
						signalWrapper.emit(pin, realValue, timer.peek().msecs);
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
				assert(command.length == 5);
				assert(command[0] == ReadCommands.varMonitor);
			}
			body
			{
				writeln("Handling varMonitorCommand ", command);

				void handleData(VarType)(ubyte varIndex, ubyte[] data)
				{
					void emitData(VarType)(ubyte varIndex, VarType data)
					{
						alias varTypeSignalWrappers = hack!(mixin(varMonitorSignalWrappersName!VarType));

						if(varIndex in varTypeSignalWrappers)
						{
							auto signalWrapper = varTypeSignalWrappers[varIndex];

							synchronized(signalWrapper)
							{
								signalWrapper.emit(varIndex, data, timer.peek().msecs);
							}
						}
						else
						{
							writeln("SignalWrapper for type ", VarType.stringof, "and varIndex ", varIndex, "was no longer in its SignalWrapper assoc array. Skipping signal emission.");
						}
					}

					pure VarType decodeData(VarType : short)(ubyte[] data)
					{
						enum ubytePossibleValues = 256;
						return to!short(data[0] * ubytePossibleValues + data[1]);
					}

					emitData(varIndex, decodeData!VarType(data));
				}

				void delegate (ubyte, ubyte[]) selectDelegate(VarMonitorTypeCode typeCode)
				{
					//TODO: this could be generated with a mixin
					final switch(typeCode) with (VarMonitorTypeCode)
					{
						case short_t:
							return &handleData!short;
					}
				}

				try
				{
					auto handler = selectDelegate(to!VarMonitorTypeCode(command[1]));
					handler(command[2], command[3..$]);
				}catch(ConvException e)
				{
					writeln("Received invalid varMonitor type: ",e);
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
				case ReadCommands.analogMonitor:
					if(readBuffer.length < 5)
						return;

					handleAnalogMonitorCommand(readBuffer[1..5]);
					popReadBuffer(5);
					break;

				case ReadCommands.varMonitor:
					if(readBuffer.length < 6)
						return;

					handleVarMonitorCommand(readBuffer[1..6]);
					popReadBuffer(6);
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
					writeln("handshake cache is currently ", cache);

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
		timer.start();

		do
		{
			ubyte[] readBytes = arduinoSerialPort.read(bytesReadAtOnce);

			if(readBytes !is null)
			{
				//writeln("Read bytes ", readBytes);
				handleReadBytes(readBytes);
			}

			receiveTimeout(msecs(receiveTimeoutMs), &handleEndCommunicationMessage,
                                                    &handlePinMonitorMessage,
                                                    &handleVarMonitorMessage,
                                                    &handleSetPWMMessage);

		}while(shouldContinue);

        void sendPuppeteerClosedCmd(ISerialPort serialPort)
		{
			writeln("Sending puppeteerClosedCommand");
			serialPort.write([commandControlByte, 0x99]);
		}
        sendPuppeteerClosedCmd(arduinoSerialPort);

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

    private struct EndCommunicationMessage
    {

    }

    private struct PinMonitorMessage
    {
        enum Action
        {
            start,
            stop
        }

        private Action action;
        private ubyte pin;

        this(Action action, ubyte pin)
        {
            this.action = action;
            this.pin = pin;
        }
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

    private struct SetPWMMessage
    {
        ubyte pin;
        ubyte value;

        this(ubyte pin, ubyte value)
        {
            this.pin = pin;
            this.value = value;
        }
    }
}
unittest
{
	assert(__traits(compiles, Puppetteer!short));
	assert(!__traits(compiles, Puppetteer!float));
	assert(!__traits(compiles, Puppetteer!(short, float)));
	assert(!__traits(compiles, Puppetteer!(short, void)));
}

private enum VarMonitorTypeCode : byte
{
	short_t = 0x0,
}

private enum isVarMonitorTypeSupported(VarType) = __traits(compiles, varMonitorTypeCode!VarType);
unittest
{
	assert(isVarMonitorTypeSupported!short);
	assert(!isVarMonitorTypeSupported!float);
	assert(!isVarMonitorTypeSupported!void);
}


private alias varMonitorTypeCode(VarType) = hack!(mixin(VarMonitorTypeCode.stringof ~ "." ~ VarType.stringof ~ "_t"));
unittest
{
	assert(varMonitorTypeCode!short == VarMonitorTypeCode.short_t);
}

private pure string unrollVariableSignalWrappers(VarTypes...)()
{
	string unroll = "";

	foreach(varType; VarTypes)
	{
		unroll ~= varMonitorSignalWrappersType!varType ~ " " ~ varMonitorSignalWrappersName!varType ~ ";\n";
	}

	return unroll;
}


private pure enum varMonitorSignalWrappersType(VarType) = "SignalWrapper!(ubyte, " ~ VarType.stringof ~ ", long)[ubyte]";
unittest
{
	assert(varMonitorSignalWrappersType!int == "SignalWrapper!(ubyte, int, long)[ubyte]");
	assert(varMonitorSignalWrappersType!float == "SignalWrapper!(ubyte, float, long)[ubyte]");
	assert(varMonitorSignalWrappersType!byte == "SignalWrapper!(ubyte, byte, long)[ubyte]");
}


private pure enum varMonitorSignalWrappersName(VarType) = VarType.stringof ~ "SignalWrappers";
unittest
{
	assert(varMonitorSignalWrappersName!int == "intSignalWrappers");
}
