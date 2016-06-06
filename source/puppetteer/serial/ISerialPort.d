module puppeteer.serial.ISerialPort;

import puppeteer.serial.BaudRate;
import puppeteer.serial.Parity;
import puppeteer.serial.OxSerialPortWrapper;

interface ISerialPort
{
	void write(ubyte[] bytes);
	ubyte[] read(int maxBytes);

	bool open();
	void close();

	static ISerialPort getInstance(string filename, Parity parity, BaudRate baudRate, uint timeOutMilliseconds)
	{
		return new OxSerialPortWrapper(filename, parity, baudRate, timeOutMilliseconds);
	}
}
