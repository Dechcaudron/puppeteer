module puppeteer.communication.is_value_emitter;

enum isValueEmitter(T, IVTs) = is(typeof(
{
    T emitter;

    emitter.emitAIRead(ubyte.init /* pin */,
                        float.init /* value */,
                        long.init /* communicationMillisTime */);

    foreach(IVT; IVTs)
        emitter.emitIVRead!IVT(ubyte.init /* varIndex */,
                                IVT.init /* value */,
                                long.init /* communicationMillisTime */);
}()));;
