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
