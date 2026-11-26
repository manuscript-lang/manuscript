// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=lent-split
// A lent `split` result used in place, and a `.clone()` that keeps it.
type Row {
	fields List[String]
}

fn latency(line String) Int {
	f := line.split(" ").collect()
	return f[1].length() + f.length()
}

fn keep(line String) Row {
	return Row(line.split(" ").collect().clone())
}

fn longest(text String) String {
	var best = ""
	for p in text.split(",") {
		if p.length() > best.length() {
			best = p.clone()
		}
	}
	return best
}

// The pieces are views of `rest`, which dies when the function returns: the clone must
// own them.
fn components(text String) List[String] {
	rest := text.cut_prefix("/") or text
	return rest.split("/").collect().clone()
}

export fn main() Int {
	print(components("/alpha/beta/gamma/delta/epsilon/zeta/eta/theta"))
	print(latency("alpha beta gamma"))
	print(keep("a b c").fields.length())
	print(longest("x,yyyy,zz,wwwwwwwwwwwwwwwwwwwwwwwwwwww"))

	var line = "one two"
	parts := line.split(" ").collect().clone()
	line = ""
	print(parts)
	return 0
}
// expect-exit: 0
// expect-stdout: [alpha, beta, gamma, delta, epsilon, zeta, eta, theta]
// expect-stdout: 7
// expect-stdout: 3
// expect-stdout: wwwwwwwwwwwwwwwwwwwwwwwwwwww
// expect-stdout: [one, two]
