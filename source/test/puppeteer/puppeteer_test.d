module test.puppeteer.puppeteer_test;

mixin template test()
{
    version(unittest)
        import unit_threaded;

    import puppeteer.communication.communication_exception;

    import puppeteer.configuration.configuration;

    import test.puppeteer.communication.broken_communicator;

    import test.puppeteer.logging.mock_logger;

    @("Test supported types")
    unittest
    {
        assert(__traits(compiles, Puppeteer!()));
        assert(__traits(compiles, Puppeteer!short));
        assert(!__traits(compiles, Puppeteer!float));
        assert(!__traits(compiles, Puppeteer!(short, float)));
        assert(!__traits(compiles, Puppeteer!(short, void)));
    }

    unittest
    {
        class Foo
        {
            void pinListener(ubyte pin, float receivedValue, float adaptedValue, long msecs) shared {}
            void varListener(T)(ubyte var, T receivedValue, T adaptedValue, long msecs) shared {}
        }

        auto a = new shared Puppeteer!(shared BrokenCommunicator!short, short)
                                        (new shared BrokenCommunicator!short(), new shared Configuration!short, new shared MockLogger);
        auto foo = new shared Foo;

        assertThrown!CommunicationException(a.endCommunication());
        assertThrown!CommunicationException(a.addPinListener(0, &foo.pinListener));
        assertThrown!CommunicationException(a.removePinListener(0, &foo.pinListener));
        assertThrown!CommunicationException(a.addVariableListener!short(0, &foo.varListener!short));
        assertThrown!CommunicationException(a.removeVariableListener!short(0, &foo.varListener!short));
    }

    unittest
    {
        auto a = new shared Puppeteer!short(new shared BrokenCommunicator!short(), new shared Configuration!short, new shared MockLogger);

        assert(a.getPWMFromAverage!5(5) == 255);
        assert(a.getPWMFromAverage!5(0) == 0);
        assert(a.getPWMFromAverage!5(1) == 51);
        assert(a.getPWMFromAverage!5(2) == 102);
        assert(a.getPWMFromAverage!5(3) == 153);

        assert(a.getPWMFromAverage!22(21) == 243);
    }
}
