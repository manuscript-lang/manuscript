// conform: tags=alternatives,control-flow,faults,formatter,match,modules,parser,records,stdlib-faults,testing,tier-stdlib
// conform: phase=parse
// conform: origin=documentation/core-language/types/named-types.md:99
import panic from "@std/core.ms"

enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
}

fn evaluate(expr Expr) Int {
	match expr {
		Num(value) => return value
		Add(left, right) => return evaluate(left) + evaluate(right)
	}
}

test "recursive expression" {
	expr := Expr.Add(Expr.Num(1), Expr.Num(2))
	if evaluate(expr) != 3 {
		panic("unexpected expression value")
	}
}
// expect-format: rewritten
// expect-formatted: import panic from "@std/core.ms"
// expect-formatted:
// expect-formatted: enum Expr {
// expect-formatted: \tNum(value Int)
// expect-formatted: \tAdd(left, right Expr)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn evaluate(expr Expr) Int {
// expect-formatted: \tmatch expr {
// expect-formatted: \t\tNum(value) => return value
// expect-formatted: \t\tAdd(left, right) => return evaluate(left) + evaluate(right)
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "recursive expression" {
// expect-formatted: \texpr := Expr.Add(Expr.Num(1), Expr.Num(2))
// expect-formatted: \tif evaluate(expr) != 3 {
// expect-formatted: \t\tpanic("unexpected expression value")
// expect-formatted: \t}
// expect-formatted: }
