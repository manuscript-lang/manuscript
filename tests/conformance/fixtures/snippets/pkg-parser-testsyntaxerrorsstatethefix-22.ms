# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:33 TestSyntaxErrorsStateTheFix
fn g(x: Int) Int:
    return x
fn f() Int:
    return g(x = 1)
