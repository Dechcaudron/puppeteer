module puppeteer.logging.basic_logger;

import puppeteer.logging.logging_exception;

import std.concurrency;
import std.stdio;
import std.conv;

package shared struct BasicLogger
{
    private static int next_id = 0;
    private int id;

    @property
    private string loggerTidName()
    {
        enum nameBase = "puppeteer.logging.basic_logger";

        return nameBase ~ to!string(id);
    }

    @property
    private Tid loggerTid()
    {
        return locate(loggerTidName);
    }

    this(string logFilename)
    {
        id = next_id++;

        Tid loggerTid = spawn(&loggingLoop, logFilename);
        register(loggerTidName, loggerTid);

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
