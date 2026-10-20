# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:52 TestPassAndIfExpressionHints
fn f(a: Int) Unit:
    if a == 1:
        pass
