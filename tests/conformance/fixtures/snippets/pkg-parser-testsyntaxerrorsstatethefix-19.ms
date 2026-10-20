# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:30 TestSyntaxErrorsStateTheFix
fn f() Int:
    for i, x in [1]:
        return i
    return 0
