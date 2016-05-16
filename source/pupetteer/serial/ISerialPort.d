module pupetteer.serial.ISerialPort;

import pupetteer.serial.BaudRate;
import pupetteer.serial.Parity;
import pupetteer.serial.OxSerialPortWrapper;

interface ISerialPort
{
	void write(ubyte[] bytes);
	ubyte[] read(int maxBytes);

	void open();
	void close();

	static ISerialPort getInstance(string filename, Parity parity, BaudRate baudRate, uint timeOutMilliseconds)
	{
		return new OxSerialPortWrapper(filename, parity, baudRate, timeOutMilliseconds);
	}
}
