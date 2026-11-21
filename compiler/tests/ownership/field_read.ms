type Person:
	name: String
	age: Int

type Team:
	lead: Person
	size: Int

fn greet(p: Person) String:
	return "hi {p.name}"

fn same(a: Person, b: Person) Bool:
	return a.name == b.name

fn lead_name(t: Team) Int:
	return t.lead.age + t.size

fn take_name(var p: Person) String:
	return p.name

fn keep_name(p: Person) Int:
	n := p.name
	return p.age
