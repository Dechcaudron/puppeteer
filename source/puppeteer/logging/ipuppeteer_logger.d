module puppeteer.logging.ipuppeteer_logger;

interface IPuppeteerLogger
{
    void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue);
    void logInfo(long timeMs, string info);
}
