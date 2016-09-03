module puppeteer.value_adapter.value_adapter;

import test.puppeteer.value_adapter.value_adapter : test;
mixin test;

import puppeteer.value_adapter.invalid_adapter_expression_exception;

import arith_eval.evaluable;

shared struct ValueAdapter(T)
{
    private Evaluable!(T, "x") evaluable;
    private string _expression;

    @property
    public string expression() const
    {
        return _expression;
    }

    @property
    private void expression(string rhs)
    {
        _expression = rhs;
    }

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
