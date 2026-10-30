# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:12 TestExpressionConvenienceRejections
fn optional(value: Int = 1) Int: return value

fn required(value: Int) Int: return value

fn call(x: Int?) Int:
    let chosen = match x:
        some(n): optional
        none: required

    return chosen()
