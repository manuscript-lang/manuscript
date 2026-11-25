// conform: tags=strings,tier-core
// conform: phase=run
// A string grown by `+=` records spare room after its text. Equal strings compare, hash
// and look up the same whether or not they carry it.
fn grown(n Int) String {
	var s = "prefix-that-is-not-inline-"
	for i in 0..n { s += "ab" }
	return s
}

fn main() Void {
	a := grown(40)
	b := "prefix-that-is-not-inline-" + "ab".repeat(40)
	print(a == b)
	print(a.length())

	var seen Map[String, Int] = {}
	seen[a.clone()] = 1
	print(seen.get_or(b, 0))

	var c = grown(3)
	c += "xyz"

	d := "prefix-that-is-not-inline-ababab" + "xyz"
	print(c == d)
	print(c < d)

	var e = a.clone()
	e += "!"
	print(e == a)
	print(e.length() - a.length())

	var small = "ab"
	small += "cd"
	print(small == "abcd")
}
// expect-exit: 0
// expect-stdout: true
// expect-stdout: 106
// expect-stdout: 1
// expect-stdout: true
// expect-stdout: false
// expect-stdout: false
// expect-stdout: 1
// expect-stdout: true
