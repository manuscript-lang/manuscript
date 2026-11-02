# conform: tags=match,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:28 TestSyntaxErrorsStateTheFix
fn f(a: Int) Int:
    match a:
        1: return 2
