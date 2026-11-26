// conform: tags=strings,interpolation,try-result,tier-core
// conform: phase=run
// A joined text evaluates its pieces left to right, and a `?` that returns early drops
// the pieces already built once and runs none of the later ones.

fn note(s String, n Int) String {
	print(f"eval {s}")
	return f"{s}{n}"
}

fn fails(n Int) String! {
	if n > 0 { return error(Error(f"bad {n}")) }
	return ok("ok")
}

fn build(n Int) String! {
	s := f"[{note("a", 1)}|{note("b", 2)}|{fails(n)?}|{note("c", 3)}]"
	return ok(s)
}

fn fill(n Int) String! {
	var out = ""
	out += "start;"
	out += f"[{note("a", 1)}|{fails(n)?}|{note("b", 2)}|{n}]"
	out += note("c", 3) + "-" + note("d", 4)
	return ok(out)
}

fn main() Int {
	print(f"{note("x", 1)}-{note("y", 2)}" + "-" + note("z", 3))

	good := build(0)
	print(good)

	bad := build(1)
	print(bad)

	var acc = ""
	for i in 0..3 {
		acc += f"{note("p", i)}{i}"
	}
	print(acc)
	print(fill(0))
	print(fill(1))
	return 0
}
// expect-exit: 0
// expect-stdout: eval x
// expect-stdout: eval y
// expect-stdout: eval z
// expect-stdout: x1-y2-z3
// expect-stdout: eval a
// expect-stdout: eval b
// expect-stdout: eval c
// expect-stdout: ok([a1|b2|ok|c3])
// expect-stdout: eval a
// expect-stdout: eval b
// expect-stdout: error(Error(details: Map(), kind: none, message: bad 1))
// expect-stdout: eval p
// expect-stdout: eval p
// expect-stdout: eval p
// expect-stdout: p00p11p22
// expect-stdout: eval a
// expect-stdout: eval b
// expect-stdout: eval c
// expect-stdout: eval d
// expect-stdout: ok(start;[a1|ok|b2|0]c3-d4)
// expect-stdout: eval a
// expect-stdout: error(Error(details: Map(), kind: none, message: bad 1))
