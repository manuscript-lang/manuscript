# conform: tags=lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:29 TestSyntaxErrorsStateTheFix
fn f(a: List[Int]) Unit:
    a[0] = 1
