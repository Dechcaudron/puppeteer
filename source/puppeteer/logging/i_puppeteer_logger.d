module puppeteer.logging.i_puppeteer_logger;


shared interface IPuppeteerLogger
{
    void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue);
    void logInfo(long timeMs, string info);

    static auto getInstance(string loggingPath)
    {
        version(unittest)
        {
            import test.puppeteer.logging.mock_logger;
            return new shared MockLogger;
        }
        else version(gnuplotCrafterLogging)
        {
            import puppeteer.logging.multifile_gnuplot_crafter_logger;
            return new shared MultifileGnuplotCrafterLogger!(5)(loggingPath);
        }
        else
        {
            import puppeteer.logging.puppeteer_logger;
            return new shared PuppeteerLogger(loggingPath);
        }
    }
}
