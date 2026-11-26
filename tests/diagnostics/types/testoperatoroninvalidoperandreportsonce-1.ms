// conform: tags=diagnostics,formatter,mutation,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/conversions_queries_test.go:47 TestOperatorOnInvalidOperandReportsOnce
fn f() Int {
	var x Int = 1
	x += 3?
	return x
}
// expect-error: MS3000 6:10 '?' requires a Result or an Optional, found Int; apply '?' to a value of type Result[T, E] or T?
