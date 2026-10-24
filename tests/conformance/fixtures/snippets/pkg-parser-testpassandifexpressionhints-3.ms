# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:53 TestPassAndIfExpressionHints
def f(a: Int) -> Int:
    let b = (2 if a == 1 else 3)

    return b
