# conform: tags=match,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:19 TestSyntaxErrorsStateTheFix
fn f(a: Int) Int:
    match a:
fn g() Int: return 1
