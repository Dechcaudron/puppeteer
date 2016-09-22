module puppeteer.puppet_link.i_puppet_link;

import std.meta;
import std.format;

import puppeteer.var_monitor_utils;

import puppeteer.puppet_link.is_ai_monitor_listener;

public interface IPuppetLink
{
    bool startCommunication();
    void endCommunication();

    void readPuppet();

    @property
    bool isCommunicationOpen();

    void setAIMonitor(ubyte AIPin, bool monitor);

    void setIVMonitor(ubyte IVIndex, VarMonitorTypeCode typeCode, bool monitor);

    void setPWMOut(ubyte PWMOutPin, ubyte value);
}
