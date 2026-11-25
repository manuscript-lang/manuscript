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
