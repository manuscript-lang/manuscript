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
	var views = List[View]()
	for i in 0..2 {
		inner := make("inner", 3)
		views.append(View(inner))
	}
	print(views[0].items[0])
}
// expect-error: MS3000 19:15 this stores a value that looks at `inner` (bound at 18:9) in a place that is used after `inner` ends; declare the owner before the place that holds the view, or store `.clone()` of the part you need
