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
// expect-error: MS3000 17:11 this stores a value that looks at `inner` (bound at 16:5) in a place that is used after `inner` ends; declare the owner before the place that holds the view, or store `.clone()` of the part you need
