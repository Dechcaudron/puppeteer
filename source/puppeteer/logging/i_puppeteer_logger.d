module puppeteer.logging.i_puppeteer_logger;

import puppeteer.logging.puppeteer_logger;
import puppeteer.logging.multifile_gnuplot_crafter_logger;

shared interface IPuppeteerLogger
{
    void logSensor(long timeMs, string sensorName, string readValue, string adaptedValue);
    void logInfo(long timeMs, string info);

    static auto getInstance(string loggingPath)
    {
        version(gnuplotCrafterLogging)
            return new shared MultifileGnuplotCrafterLogger!(5)(loggingPath);
        else
            return new shared PuppeteerLogger(loggingPath);
    }
}
