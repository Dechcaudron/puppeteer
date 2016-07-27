module test.puppeteer.puppeteer_test;

mixin template test()
{
    unittest
    {
        // Test for supported types
        assert(__traits(compiles, Puppeteer!()));
        assert(__traits(compiles, Puppeteer!short));
        assert(!__traits(compiles, Puppeteer!float));
        assert(!__traits(compiles, Puppeteer!(short, float)));
        assert(!__traits(compiles, Puppeteer!(short, void)));

        class Foo
        {
            void pinListener(ubyte pin, float receivedValue, float adaptedValue, long msecs) shared
            {

            }

            void varListener(T)(ubyte var, T receivedValue, T adaptedValue, long msecs) shared
            {

            }
        }

        auto a = new Puppeteer!short();
        auto foo = new shared Foo;

        assertThrown!CommunicationException(a.endCommunication());
        assertThrown!CommunicationException(a.addPinListener(0, &foo.pinListener));
        assertThrown!CommunicationException(a.removePinListener(0, &foo.pinListener));
        assertThrown!CommunicationException(a.addVariableListener!short(0, &foo.varListener!short));
        assertThrown!CommunicationException(a.removeVariableListener!short(0, &foo.varListener!short));
    }

    unittest
    {
        auto a = new Puppeteer!short();

        assert(a.getPWMFromAverage!5(5) == 255);
        assert(a.getPWMFromAverage!5(0) == 0);
        assert(a.getPWMFromAverage!5(1) == 51);
        assert(a.getPWMFromAverage!5(2) == 102);
        assert(a.getPWMFromAverage!5(3) == 153);

        assert(a.getPWMFromAverage!22(21) == 243);
    }

    unittest
    {
        import std.json;
        import std.file;
        import std.format : format;

        auto a = new Puppeteer!short();
        a.setAIValueAdapter(0, "x");
        a.setAIValueAdapter(3, "5+x");
        a.setVarMonitorValueAdapter!short(1, "-x");
        a.setVarMonitorValueAdapter!short(5, "x-3");

        JSONValue ai = JSONValue(["0" : "x", "3" : "5+x"]);
        JSONValue shorts = JSONValue(["1" : "-x", "5" : "x-3"]);
        JSONValue vars = JSONValue(["short" : shorts]);
        JSONValue mockConfig = JSONValue([configAIAdaptersKey : ai, configVarAdaptersKey : vars]);

        assert(a.generateConfigString() == mockConfig.toPrettyString());

        enum testResDir = "test_out";
        enum configFilename1 = testResDir ~ "/config1.test";

        if(!exists(testResDir))
            mkdir(testResDir);
        else
            assert(isDir(testResDir), format("Please remove the '%s' file so the tests can run", testResDir));

        assert(a.saveConfig(configFilename1));

        auto b = new Puppeteer!short();

        b.loadConfig(configFilename1);

        assert(b.generateConfigString() == mockConfig.toPrettyString());

        auto c = new Puppeteer!()();
        assertThrown!InvalidConfigurationException(c.loadConfig(configFilename1));

        auto d = new Puppeteer!()();
        d.setAIValueAdapter(0, "2*x");
        d.setAIValueAdapter(5, "-3*x");

        enum configFilename2 = testResDir ~ "/config2.test";

        assert(d.saveConfig(configFilename2));

        auto e = new Puppeteer!short();

        assert(e.loadConfig(configFilename2));

        assert(d.generateConfigString() == e.generateConfigString());
    }
}
