// conform: tags=alternatives,formatter,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:18 TestRecursiveDataAndFiniteTypeApplications
enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
	Neg(inner Expr?)
}
// expect-format: rewritten
// expect-formatted: enum Expr {
// expect-formatted: \tNum(value Int)
// expect-formatted: \tAdd(left, right Expr)
// expect-formatted: \tNeg(inner Expr?)
// expect-formatted: }
