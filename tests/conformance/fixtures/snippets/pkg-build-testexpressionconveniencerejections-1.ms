# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:12 TestExpressionConvenienceRejections
def optional(value: Int = 1) -> Int: return value

def required(value: Int) -> Int: return value

def call(x: Optional[Int]) -> Int:
    let chosen = match x:
        case some(n): optional
        case none: required

    return chosen()
