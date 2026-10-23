# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:12 TestExpressionConvenienceRejections
fn optional(value: Int = 1) Int: return value

fn required(value: Int) Int: return value

fn call(x: Optional[Int]) Int:
    let chosen = match x:
        some(n): optional
        none: required

    return chosen()
