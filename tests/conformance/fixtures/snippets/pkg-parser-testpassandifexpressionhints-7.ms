# conform: tags=interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:57 TestPassAndIfExpressionHints
fn f() String:
    return "{\"a\": 1}"
