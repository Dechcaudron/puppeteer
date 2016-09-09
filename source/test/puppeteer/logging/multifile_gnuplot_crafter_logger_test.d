module test.puppeteer.logging.multifile_gnuplot_crafter_logger_test;

mixin template test()
{
    import std.stdio;
    import std.string;

    unittest
    {
        auto logger = new shared MultifileGnuplotCrafterLogger!(10)("test_out/");

        logger.logSensor(0, "var1", "", "3");
        logger.logSensor(3, "var2", "", "4");
        logger.logSensor(1, "var1", "", "0.01");
        logger.logSensor(5, "var2", "", "3.234");

        string var1Path = logger.getPathForSensorData("var1");
        string var2Path = logger.getPathForSensorData("var2");

        destroy(logger);

        string s;

        File var1File = File(var1Path, "r");
        var1File.readf("%s", &s);

        assert(s.chomp() == "0 3" ~ "\n" ~ "1 0.01");

        File var2File = File(var2Path, "r");
        var2File.readf("%s", &s);

        assert(s.chomp() == "3 4" ~ "\n" ~ "5 3.234");
    }
}
