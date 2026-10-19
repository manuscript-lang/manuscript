# conform: tags=interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:55 TestPassAndIfExpressionHints
fn f() String:
    return "function() { return 1; }"
