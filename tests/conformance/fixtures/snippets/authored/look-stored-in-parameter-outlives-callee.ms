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

fn fill(var views List[View]) Void {
	inner := make("inner", 3)
	views.append(View(inner))
}

fn main() Void {
	var views = List[View]()
	fill(views)
	print(views.length())
}
