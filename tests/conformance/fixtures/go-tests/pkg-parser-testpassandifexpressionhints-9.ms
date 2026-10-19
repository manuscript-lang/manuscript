# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:59 TestPassAndIfExpressionHints
fn f(a: Int, b: Int) Bool:
    return a > 0
        and b > 0
