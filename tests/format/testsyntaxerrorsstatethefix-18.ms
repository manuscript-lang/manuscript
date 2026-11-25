// conform: tags=lists,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/parser/hints_test.go:29 TestSyntaxErrorsStateTheFix
fn f(a List[Int]) Void {
	a[0] = 1
}
