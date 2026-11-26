// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:34 TestRecursiveTypesPreserveInitializationAndHashing
enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
}

fn value(expr Expr) Int {
	match expr {
		Num(value) => return value
	}
}
// expect-format: rewritten
// expect-formatted: enum Expr {
// expect-formatted: \tNum(value Int)
// expect-formatted: \tAdd(left, right Expr)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn value(expr Expr) Int {
// expect-formatted: \tmatch expr {
// expect-formatted: \t\tNum(value) => return value
// expect-formatted: \t}
// expect-formatted: }
