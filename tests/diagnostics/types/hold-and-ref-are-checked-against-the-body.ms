// conform: tags=diagnostics
// conform: phase=check
// A signature that writes `hold` or `&` is checked against its body: a result may be a part of a held argument only.
type Person {
	name String
}

fn pick(hold a Person, b Person) &String {
	return b.name
}

fn hold Person.fresh() &String {
	return "x"
}

fn amp_without_hold(p Person) &String {
	return p.name
}

fn ok_pick(hold a Person, b Person) &String {
	return a.name
}

fn main() Void {
	p := Person(name: "x")
	print(ok_pick(p, p))
}
// expect-error: MS3000 8:1 the result is a part of `b`, so the signature must say `hold` for it; write `hold` before it, or return a `.clone()`
// expect-error: MS3000 12:16 a `&` result must be a part of a `hold` argument, but this body returns a new value; remove the `&` or return a part of the held argument
// expect-error: MS3000 16:1 a `&` result points into an argument; mark that argument `hold`, or return an owned value
