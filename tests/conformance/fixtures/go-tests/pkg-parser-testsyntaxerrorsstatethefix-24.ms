# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:35 TestSyntaxErrorsStateTheFix
fn f() Int:
    throw "x"
    return 0
