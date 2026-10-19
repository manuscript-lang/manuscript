# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:23 TestSyntaxErrorsStateTheFix
fn f() Int:
    1 + 1
    return 1
