# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:38 TestRejectSyntax
fn f(value: fn(x: Int = 1) Int) Unit:
    return
