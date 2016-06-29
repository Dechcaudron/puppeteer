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

    override void logAI(long timeMs, ubyte pin, float readValue, float adaptedValue)
    {
        logger.log(format("%s:AI%s:%s:%s", timeMs, pin, readValue, adaptedValue));
    }

    void logVar(long timeMs, string varTypeName, ubyte varIndex, string readValue, string adaptedValue)
    {
        logger.log(format("%s:Var[%s]%s:%s:%s", timeMs, varTypeName, varIndex, readValue, adaptedValue));
    }

    void logInfo(long timeMs, string info)
    {
        logger.log(format("#%s : %s", timeMs, info));
    }
}
