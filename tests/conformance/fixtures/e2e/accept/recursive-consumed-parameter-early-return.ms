// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

enum Expr:
	Num(n: Int)
	Var(name: String)
	Keep(name: String)
	Add(l: Expr, r: Expr)

// `Keep` moves its payload out, so `eval` consumes `e`. The recursive calls pass the
// payloads on; an early `?` return from the second one must not drop it again.
fn eval(e: Expr) Int!:
	match e:
		Num(n): return ok(n)
		Var(name): return error(Error("unbound {name}"))
		Keep(name):
			xs := [name]
			return ok(xs.length())
		Add(l, r):
			a := eval(l)?
			b := eval(r)?
			return ok(a + b)

test "second operand fails after the first succeeded":
	r := eval(Expr.Add(Expr.Num(1), Expr.Var("y")))
	expect_true(r.is_error())?
	expect_equal(r.err().message, "unbound y")?

test "both operands succeed":
	expect_equal(eval(Expr.Add(Expr.Num(1), Expr.Keep("k"))).get(0), 2)?
