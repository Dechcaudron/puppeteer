module puppeteer.serial.i_serial_port;

public import puppeteer.serial.baud_rate;
public import puppeteer.serial.parity;
import puppeteer.serial.ox_serial_port_wrapper;

interface ISerialPort
{
	void write(ubyte[] bytes);
	ubyte[] read(int maxBytes);

	bool open();
	void close();

    @property
    bool isOpen();

	static ISerialPort getInstance(string filename, Parity parity, BaudRate baudRate, uint timeOutMilliseconds)
	{
		return new OxSerialPortWrapper(filename, parity, baudRate, timeOutMilliseconds);
	}
}
