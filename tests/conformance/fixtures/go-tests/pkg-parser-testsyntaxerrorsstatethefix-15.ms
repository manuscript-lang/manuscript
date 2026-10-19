# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:26 TestSyntaxErrorsStateTheFix
fn f() Int:
    for i in 0..10:
        return i
    return 0
