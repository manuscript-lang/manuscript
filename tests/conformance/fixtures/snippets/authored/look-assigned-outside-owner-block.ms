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

fn main() Void {
	base := make("base", 2)
	var held = View(base)
	for i in 0..2 {
		inner := make("inner", 3)
		held = View(inner)
	}
	print(held.items[0])
}
