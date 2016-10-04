module test.puppeteer.logging.mock_logger;

import puppeteer.logging.i_puppeteer_logger;

public shared class MockLogger : IPuppeteerLogger
{
    void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue) {}
    void logInfo(long timeMs, string info) {}
}
