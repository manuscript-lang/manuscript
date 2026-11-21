import scale, twice from "./util.ms"

fn bump(x: Int) Int:
	return x + 100

fn main() Int:
	a := twice(bump(1))
	b := scale(1.5, 2.0)
	if b > 2.0: return a

	return 0
