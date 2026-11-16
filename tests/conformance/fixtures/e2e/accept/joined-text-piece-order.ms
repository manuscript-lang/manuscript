// conform: tags=strings,interpolation,try-result,tier-core
// conform: phase=run
// A joined text evaluates its pieces left to right, and a `?` that returns early drops
// the pieces already built once and runs none of the later ones.
fn note(s: String, n: Int) String:
	print("eval {s}")
	return "{s}{n}"

fn fails(n: Int) String!:
	if n > 0: return error(Error("bad {n}"))
	return ok("ok")

fn build(n: Int) String!:
	s := "[{note("a", 1)}|{note("b", 2)}|{fails(n)?}|{note("c", 3)}]"
	return ok(s)

fn main() Int:
	print("{note("x", 1)}-{note("y", 2)}" + "-" + note("z", 3))

	good := build(0)
	print(good)

	bad := build(1)
	print(bad)

	var acc = ""
	for i in 0..3:
		acc += "{note("p", i)}{i}"
	print(acc)
	return 0
