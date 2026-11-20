type Person:
	name: String
	age: Int

fn make(name: String) Person:
	return Person(name, 3)

fn greet(p: Person) String:
	return p.name

fn age_of(p: Person) Int:
	return p.age

fn local() Int:
	p := make("a")
	return age_of(p)

fn build(move name: String) Person:
	return Person(name, 4)

fn main() Int:
	q := build("z")
	return local() + age_of(q)
