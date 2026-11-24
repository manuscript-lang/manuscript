// conform: tags=ownership,var-parameters
// conform: phase=run
type Gate {
	count Int
	open Bool
	note String
}

fn bump(var gate Gate) Void {
	gate.count += 1
	gate.open = true
}

fn check(var gate Gate) String {
	gate.count += 1
	return gate.note.clone()
}

fn both(var a Gate, var b Gate) Void {
	bump(a)
	bump(b)
	bump(b)
}

fn main() Void {
	var a = Gate(0, false, "fresh")
	var b = Gate(10, false, "kept")
	both(a, b)
	print(f"{a.count} {b.count} {a.open} {b.open}")
	print(check(a))
	print(check(b))
}
