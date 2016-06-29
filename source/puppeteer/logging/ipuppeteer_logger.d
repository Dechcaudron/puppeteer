module puppeteer.logging.ipuppeteer_logger;

interface IPuppeteerLogger
{
    void logAI(long timeMs, ubyte pin, float readValue, float adaptedValue);
    void logVar(long timeMs, string varTypeName, ubyte varIndex, string readValue, string adaptedValue);
    void logInfo(long timeMs, string info);
}
