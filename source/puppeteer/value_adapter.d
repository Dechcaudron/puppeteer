module puppeteer.value_adapter;

import puppeteer.exception.invalid_adapter_expression_exception;

import arith_eval.evaluable;

import test.puppeteer.value_adapter : test;
mixin test;

shared struct ValueAdapter(T)
{
    private Evaluable!(T, "x") evaluable;
    private string _expression;

    @property
    public string expression()
    {
        return _expression;
    }

    @property
    private void expression(string rhs)
    {
        _expression = expression;
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
