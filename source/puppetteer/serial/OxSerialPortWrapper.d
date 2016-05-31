module puppetteer.serial.OxSerialPortWrapper;

import puppetteer.serial.ISerialPort;
import puppetteer.serial.BaudRate;
import puppetteer.serial.Parity;

import onyx.serial : OnyxParity = Parity, OnyxBaudRate = Speed;
import onyx.serial : OxSerialPort, SerialPortTimeOutException;

class OxSerialPortWrapper : ISerialPort
{
	private OxSerialPort port;

	this(string filename, Parity parity, BaudRate baudRate, uint timeOutMilliseconds)
	{
		OnyxParity mapParity(Parity parity)
		{
			final switch (parity)
			{
				case Parity.none:
					return OnyxParity.none;

				case Parity.odd:
					return OnyxParity.odd;

				case Parity.even:
					return OnyxParity.even;
			}
		}

		OnyxBaudRate mapBaudRate(BaudRate baudRate)
		{
			final switch (baudRate)
			{
				case BaudRate.B9600:
					return OnyxBaudRate.B9600;
			}
		}

		port = OxSerialPort(filename, mapBaudRate(baudRate), mapParity(parity), timeOutMilliseconds);
	}

	public bool open()
	{
		if(!port.isOpen)
			port.open();

		return port.isOpen();
	}

	public void close()
	{
		if(port.isOpen)
			port.close();
	}

	public void write(ubyte[] bytes)
	{
		port.write(bytes);
	}

	public ubyte[] read(int maxBytes)
	{
		try
		{
			return port.read(maxBytes);
		}
		catch(SerialPortTimeOutException)
		{
			return null;
		}
	}
}