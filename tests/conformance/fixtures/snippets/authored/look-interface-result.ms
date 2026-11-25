// conform: tags=types,interfaces
// conform: phase=run
interface Source {
	hold fn items() &List[String]
}

type Bag {
	names List[String]
}

fn hold Bag.items() &List[String] {
	return self.names
}

fn first(hold s Source) &String {
	return s.items()[0]
}

fn main() Void {
	var b = Bag(["a", "b"])
	s := first(b)
	print(s)
}
