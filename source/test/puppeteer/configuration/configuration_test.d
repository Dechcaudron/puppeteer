module test.puppeteer.configuration.configuration_test;

mixin template test()
{
    import std.json;
    import std.file;
    import std.format;
    import std.exception;

    unittest
    {
        auto a = new shared Configuration!short;

        a.setAIValueAdapterExpression(0, "x");
        a.setAIValueAdapterExpression(3, "5+x");
        a.setVarMonitorValueAdapterExpression!short(1, "-x");
        a.setVarMonitorValueAdapterExpression!short(5, "x-3");

        JSONValue ai = JSONValue(["0" : "x", "3" : "5+x"]);
        JSONValue shorts = JSONValue(["1" : "-x", "5" : "x-3"]);
        JSONValue vars = JSONValue(["short" : shorts]);
        JSONValue mockConfig = JSONValue([configAIAdaptersKey : ai, configVarAdaptersKey : vars]);

        string aSaved = a.save();
        assert(aSaved == mockConfig.toPrettyString());

        File aSavedTmp = File.tmpfile();
        assert(aSavedTmp.isOpen);
        auto a2 = new shared Configuration!short;

        a.save(aSavedTmp);
        aSavedTmp.rewind();
        a2.load(aSavedTmp);
        assert(aSaved == a2.save());

        auto b = new shared Configuration!short;

        b.load(aSaved);

        assert(b.save() == mockConfig.toPrettyString());

        auto c = new shared Configuration!();
        assertThrown!InvalidConfigurationException(c.load(aSaved));
        assertThrown!InvalidConfigurationException(c.load("rAnDoooM TeXXt"));

        auto d = new shared Configuration!();
        d.setAIValueAdapterExpression(0, "2*x");
        d.setAIValueAdapterExpression(5, "-3*x");

        string dSaved = d.save();

        auto e = new shared Configuration!short();
        e.load(dSaved);

        assert(dSaved == e.save());
    }
}
