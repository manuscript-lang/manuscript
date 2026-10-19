# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:16 TestSyntaxErrorsStateTheFix
fn f() Int:
    let s = "abc
    return 1
