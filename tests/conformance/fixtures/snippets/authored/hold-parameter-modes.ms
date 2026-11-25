// conform: phase=run
// conform: origin=design/proposals/argument-modes-in-signatures.md
type Person {
	name String
}

fn hold Person.name_of() String {
	return self.name
}

fn var hold Person.rename(value String) Void {
	self.name = value
}

fn pick(hold a Person, b Person) String {
	return a.name
}

fn apply(f fn(hold Person) String, p Person) String {
	return f(p)
}

interface Named {
	hold fn name() String
	var hold fn rename(v String) Void
}

fn hold(slot Int) Int {
	return slot
}

fn main() Void {
	var p = Person(name: "x")
	p.rename("y")
	print(pick(p, p))
	print(p.name_of())
	print(apply(q => q.name, p))
	print(hold(3))
}
