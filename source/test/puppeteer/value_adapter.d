module test.puppeteer.value_adapter;

mixin template test()
{
    unittest
    {
        auto a = shared ValueAdapter!float("x / 3");
        assert(a(3) == 1.0f);
        assert(a(1) == 1.0f / 3);

        auto b = shared ValueAdapter!float("x**2 + 1");
        assert(b(3) == 10.0f);
        assert(b(5) == 26.0f);

        b = shared ValueAdapter!float("x");
        assert(b(1) == 1f);

        auto c = shared ValueAdapter!int("x * 3");
        assert(c(3) == 9);
    }
}
