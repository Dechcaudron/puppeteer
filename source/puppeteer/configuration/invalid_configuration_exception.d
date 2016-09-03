module puppeteer.configuration.invalid_configuration_exception;

public class InvalidConfigurationException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, null);
    }
}
