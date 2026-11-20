fn pick(a: Int, b: Int) Int?:
	if a > b: return a
	return none

fn or_zero(o: Int?) Int:
	if v := o: return v
	return 0

fn safe(n: Int) Result[Int, Int]:
	if n < 0: return error(n)
	return ok(n + 1)

fn twice(n: Int) Result[Int, Int]:
	m := safe(n)?
	return ok(m * 2)

fn main() Int:
	a := or_zero(pick(3, 2))
	if v := twice(a): return v

	return a
