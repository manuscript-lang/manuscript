// conform: tags=ownership,sets
// conform: phase=check
fn first_of(hold s Set[String]) &String? {
	return s.values().first()
}

fn main() Void {
	var s = Set[String]()
	s.add("a")
	print(first_of(s))
}
// expect-error: MS3000 3:1 a `&` result must be a part of a `hold` argument, but this body returns a new value; remove the `&` or return a part of the held argument
