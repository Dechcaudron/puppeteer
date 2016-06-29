module puppeteer.logging.logging_exception;

class LoggingException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, null);
    }
}
