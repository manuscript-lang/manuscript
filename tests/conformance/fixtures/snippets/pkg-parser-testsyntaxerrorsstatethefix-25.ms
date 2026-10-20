# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:36 TestSyntaxErrorsStateTheFix
fn f() Int:
    return [1][0:2]
