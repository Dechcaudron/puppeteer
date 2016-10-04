module puppeteer.logging.multifile_gnuplot_crafter_logger;

import test.puppeteer.logging.multifile_gnuplot_crafter_logger_test : test;
mixin test;

import puppeteer.logging.i_puppeteer_logger;
import puppeteer.logging.basic_logger;

import gnuplot_crafter.multithreaded.singlevar_crafter;

import std.conv;
import std.stdio;

import core.atomic;

public shared class MultifileGnuplotCrafterLogger(size_t flushCounter) : IPuppeteerLogger
{
    string dataFilesPath;
    SingleVarCrafter!(float)*[string] crafters;
    size_t[string] counters;

    this(string dataFilesPath)
    {
        //TODO: check for valid path
        this.dataFilesPath = dataFilesPath;
    }

    ~this()
    {
        debug writeln("Destroying logger");
        //Delete all allocated structs
        foreach(shared SingleVarCrafter!(float)* crafterPtr; crafters)
        {
            debug writeln("Finalizing crafter");
            crafterPtr.__dtor(); // Destroy does not call the destructor :(
            debug writeln("Destructor called");
            destroy(crafterPtr);
            debug writeln("Crafter destroyed");
        }
        crafters.clear();
        debug writeln("Logger destroyed");
    }

    private string getPathForSensorData(string sensorName)
    {
        return dataFilesPath ~ sensorName ~ ".dat";
    }

    public void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue)
    {
        auto crafterPtr = sensorName in crafters;

        if(crafterPtr !is null)
        {
            crafters[sensorName].put(to!float(timeMs), to!float(adaptedValue));

            auto counterPtr = sensorName in counters;

            atomicOp!"+="(*counterPtr, 1);
            if(*counterPtr >= flushCounter)
            {
                crafters[sensorName].flush();
                *counterPtr = 0;
            }
        }
        else
        {
            crafters[sensorName] = new shared SingleVarCrafter!float(getPathForSensorData(sensorName), false);
            crafters[sensorName].put(to!float(timeMs), to!float(adaptedValue));
            counters[sensorName] = 1;
        }
    }

    public void logInfo(long timeMs, string info)
    {
        //Do nothing!!
    }
}
