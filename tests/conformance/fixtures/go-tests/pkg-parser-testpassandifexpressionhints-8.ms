# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:58 TestPassAndIfExpressionHints
fn f() String:
    return "a}"
