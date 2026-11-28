// conform: tags=diagnostics,types,tier-core
// conform: phase=check,parse
fn main() Void {
	text := "a"
	print(-text)

	flag := true
	print(-flag)

	items := [1]
	print(+ items)
}
// expect-error: MS3000 5:11 unary - requires a numeric operand, found String
// expect-error: MS3000 8:11 unary - requires a numeric operand, found Bool
// expect-error: MS3000 11:11 unary + requires a numeric operand, found List[Int]
