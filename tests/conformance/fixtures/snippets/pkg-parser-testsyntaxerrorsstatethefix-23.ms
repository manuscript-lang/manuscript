# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:34 TestSyntaxErrorsStateTheFix
fn f() Int:
    const x = 1
    return x
