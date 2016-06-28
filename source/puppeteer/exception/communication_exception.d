module puppeteer.exception.communication_exception;

public class CommunicationException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, null);
    }
}
