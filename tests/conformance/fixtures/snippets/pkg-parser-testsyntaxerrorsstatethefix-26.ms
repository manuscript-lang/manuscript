# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:37 TestSyntaxErrorsStateTheFix
fn f() Int:
    if true && false:
        return 1
    return 0
