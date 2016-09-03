module puppeteer.value_adapter.invalid_adapter_expression_exception;

public class InvalidAdapterExpressionException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, null);
    }
}
