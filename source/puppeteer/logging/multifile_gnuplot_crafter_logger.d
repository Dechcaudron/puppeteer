module puppeteer.logging.multifile_gnuplot_crafter_logger;

import test.puppeteer.logging.multifile_gnuplot_crafter_logger_test : test;
mixin test;

import puppeteer.logging.ipuppeteer_logger;
import puppeteer.logging.basic_logger;

import gnuplot_crafter.multithreaded.singlevar_crafter;

import std.conv;
import std.stdio;

public shared class MultifileGnuplotCrafterLogger : IPuppeteerLogger
{
    string dataFilesPath;
    SingleVarCrafter!(float)*[string] crafters;

    this(string dataFilesPath)
    {
        //TODO: check for valid path
        this.dataFilesPath = dataFilesPath;
    }

    ~this()
    {
        writeln("logger destructor called");
        //Delete all allocated structs
        foreach(shared SingleVarCrafter!(float)* crafterPtr; crafters)
        {
            writeln("destroying one crafter");
            crafterPtr.__dtor(); // Destroy does not call the destructor :(
            destroy(crafterPtr);
        }
    }

    private string getPathForSensorData(string sensorName)
    {
        return dataFilesPath ~ sensorName ~ ".dat";
    }

    public void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue)
    {
        auto crafterPtr = sensorName in crafters;

        if(crafterPtr !is null)
            crafters[sensorName].put(to!float(timeMs), to!float(adaptedValue));
        else
        {
            writeln("creating one crafter");
            crafters[sensorName] = new shared SingleVarCrafter!float(getPathForSensorData(sensorName), false);
            crafters[sensorName].put(to!float(timeMs), to!float(adaptedValue));
        }
    }

    public void logInfo(long timeMs, string info)
    {
        //Do nothing!!
    }
}
