module puppeteer.serial.ox_serial_port_wrapper;

import puppeteer.serial.iserial_port;
import puppeteer.serial.baud_rate;
import puppeteer.serial.parity;

import onyx.serial : OnyxParity = Parity, OnyxBaudRate = Speed;
import onyx.serial : OxSerialPort, SerialPortTimeOutException;

class OxSerialPortWrapper : ISerialPort
{
	private OxSerialPort port;

    @property
    public bool isOpen()
    {
        return port.isOpen;
    }

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
					return OnyxBaudRate.S9600;
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
