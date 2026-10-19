# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:27 TestSyntaxErrorsStateTheFix
fn f() Int:
    let p = (1, 2)
    return 0
