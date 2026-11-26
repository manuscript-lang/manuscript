// conform: tags=ownership,records
// conform: phase=run
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
	names := make("name", 3)
	var views = List[View]()
	for i in 0..2 {
		views.append(View(names))
	}
	var held = View(names)
	for i in 0..2 {
		inner := make("inner", 2)
		local := View(inner)
		print(local.items[1])
		held = View(names)
	}
	print(views[1].items[2])
	print(held.items[0])
}
// expect-exit: 0
// expect-stdout: inner1
// expect-stdout: inner1
// expect-stdout: name2
// expect-stdout: name0
