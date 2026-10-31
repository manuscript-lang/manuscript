# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:53 TestPassAndIfExpressionHints
fn f(a: Int) Int:
    let b = (if a == 1: 2 else: 3)

    return b
