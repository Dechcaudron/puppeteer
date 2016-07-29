module puppeteer.value_adapter;

import arith_eval.evaluable;

import test.puppeteer.value_adapter : test;
mixin test;

struct ValueAdapter(T)
{
    private Evaluable!(T, "x") evaluable;
    private string expression;

    this(string xBasedValueAdapterExpr)
    {
        try
        {
            evaluable = Evaluable!(T,"x")(xBasedValueAdapterExpr);
        }
        catch(InvalidExpressionException e)
        {
            throw new InvalidAdapterExpressionException("Can't create ValueAdapter with expression " ~ xBasedValueAdapterExpr);
        }

        expression = xBasedValueAdapterExpr;
    }

    T opCall(T value) const
    {
        return evaluable(value);
    }
}
