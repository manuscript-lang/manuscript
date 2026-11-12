enum Expr:
	Num(value: Int)
	Add(left: Expr, right: Expr)
	Mul(left: Expr, right: Expr)
	Neg(inner: Expr)

fn build(depth: Int, seed: Int) Expr:
	if depth == 0: return Expr.Num(seed % 10)

	k := seed % 5
	if k == 0: return Expr.Neg(build(depth - 1, seed * 7 + 1))
	if k == 1: return Expr.Mul(
		left: build(depth - 1, seed * 3 + 1),
		right: build(depth - 1, seed + 3),
	)

	return Expr.Add(
		left: build(depth - 1, seed * 5 + 2),
		right: build(depth - 1, seed * 11 + 3),
	)

fn evaluate(expr: Expr) Int:
	match expr:
		Num(value): return value
		Add(left, right): return (evaluate(left) + evaluate(right)) % 1000003
		Mul(left, right): return (evaluate(left) * evaluate(right)) % 1000003
		Neg(inner): return -evaluate(inner)

fn case_b() Int:
	var t = 0

	for r in 0..4:
		e := build(20, r + 2)
		for k in 0..10:
			t = (t + evaluate(e)) % 1000003

	return t

fn main() Unit:
	print(case_b())
