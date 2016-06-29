module puppeteer.logging.basic_logger;

import puppeteer.logging.logging_exception;

import std.concurrency;
import std.stdio;

struct BasicLogger
{
    Tid loggerTid;

    this(string logFilename)
    {
        loggerTid = spawn(&loggingLoop, logFilename);

        receive(
            (LoopInitializedMessage msg)
            {
                if(!msg.success)
                    throw new LoggingException(msg.errorMsg);
            }
        );
    }

    void log(string message)
    {
        loggerTid.send(message);
    }

    ~this()
    {
        if(loggerTid != Tid.init)
            loggerTid.send(EndLoggingMessage());
    }
}

private void loggingLoop(string logFilename)
{
    import std.stdio;
    import std.exception : ErrnoException;

    File loggingFile;

    try
    {
        loggingFile = File(logFilename, "a");
    }
    catch(ErrnoException e)
    {
        ownerTid.send(LoopInitializedMessage(false, "Could not open logging file " ~ logFilename ~ "."));
        return;
    }

    ownerTid.send(LoopInitializedMessage(true));

    bool shouldContinue = true;

    while(shouldContinue)
    {
        receive(
            (string msg)
            {
                loggingFile.writeln(msg);
                loggingFile.flush();
            },
            (EndLoggingMessage msg)
            {
                shouldContinue = false;
            }
        );
    }
}

private struct LoopInitializedMessage
{
    bool success;
    string errorMsg;

    this(bool success, string errorMsg = "")
    body
    {
        this.success = success;
    }
}

private struct EndLoggingMessage
{

}
