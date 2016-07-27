module puppeteer.logging.puppeteer_logger;

import puppeteer.logging.ipuppeteer_logger;
import puppeteer.logging.basic_logger;

import std.format : format;

class PuppeteerLogger : IPuppeteerLogger
{
    BasicLogger logger;

    this(string logFilename)
    {
        logger = BasicLogger(logFilename);
    }

    void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue)
    {
        logger.log(format("[%s]%s:%s:%s", timeMs, sensorName, readValue, adaptedValue));
    }

    void logInfo(long timeMs, string info)
    {
        logger.log(format("#%s : %s", timeMs, info));
    }
}
