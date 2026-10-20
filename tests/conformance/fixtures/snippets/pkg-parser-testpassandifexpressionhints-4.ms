# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:54 TestPassAndIfExpressionHints
fn f(a: Int) Int:
    return 1 + (if a == 1: 1 else: 0)
