// conform: tags=ownership,records
// conform: phase=check
type View {
	items &List[String]
}

fn make(prefix String, n Int) List[String] {
	var out = List[String]()
	for i in 0..n {
		out.append(f"{prefix}{i}")
	}
	return out
}

fn counter() fn() String {
	owner := make("item", 5)
	view := View(owner)
	return fn() String {
		return view.items[0]
	}
}

fn main() Void {
	next := counter()
	print(next())
}
