module test.puppeteer.puppeteer_test;

mixin template test()
{
    version(unittest)
        import unit_threaded;

    import puppeteer.puppeteer_creator;

    import puppeteer.communication.communication_exception;

    import puppeteer.configuration.configuration;

    import test.puppeteer.communication.broken_communicator;

    import test.puppeteer.logging.mock_logger;

    @("Test supported types")
    unittest
    {
        assert(__traits(compiles, getPuppeteer!()));
        assert(__traits(compiles, getPuppeteer!short));
        assert(!__traits(compiles, getPuppeteer!float));
        assert(!__traits(compiles, getPuppeteer!(short, float)));
        assert(!__traits(compiles, getPuppeteer!(short, void)));
    }

    unittest
    {
        class Foo
        {
            void pinListener(ubyte pin, float receivedValue, float adaptedValue, long msecs) shared {}
            void varListener(T)(ubyte var, T receivedValue, T adaptedValue, long msecs) shared {}
        }

        auto a = getPuppeteer!short;
        auto foo = new shared Foo;

        assertThrown!CommunicationException(a.endCommunication());
        assertThrown!CommunicationException(a.addPinListener(0, &foo.pinListener));
        assertThrown!CommunicationException(a.removePinListener(0, &foo.pinListener));
        assertThrown!CommunicationException(a.addVariableListener!short(0, &foo.varListener!short));
        assertThrown!CommunicationException(a.removeVariableListener!short(0, &foo.varListener!short));
    }

    unittest
    {
        auto a = getPuppeteer!short;

        assert(a.getPWMFromAverage!5(5) == 255);
        assert(a.getPWMFromAverage!5(0) == 0);
        assert(a.getPWMFromAverage!5(1) == 51);
        assert(a.getPWMFromAverage!5(2) == 102);
        assert(a.getPWMFromAverage!5(3) == 153);

        assert(a.getPWMFromAverage!22(21) == 243);
    }
}
