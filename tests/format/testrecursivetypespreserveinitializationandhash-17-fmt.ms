// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:50 TestRecursiveTypesPreserveInitializationAndHashing
enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
}

fn tree() Expr => return Expr.Add(left: Expr.Num(1), right: Expr.Num(2))
// expect-format: rewritten
// expect-formatted: enum Expr {
// expect-formatted: \tNum(value Int)
// expect-formatted: \tAdd(left, right Expr)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn tree() Expr => return Expr.Add(left: Expr.Num(1), right: Expr.Num(2))
