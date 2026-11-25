// conform: tags=ownership,interfaces
// conform: phase=check
interface Source {
	hold fn items() &List[String]
}

type Bag {
	names List[String]
}

fn Bag.items() List[String] {
	return self.names.clone()
}

fn first(hold s Source) &String {
	return s.items()[0]
}

fn main() Void {
	var b = Bag(["a", "b"])
	s := first(b)
	print(s)
}
// expect-error: MS3001 21:16 expected Source, found Bag (in argument 's' of first); Bag does not satisfy Source by its own methods (items must return a `&` result, as the interface does); declare each operation as a method of Bag with the interface's exact signature
