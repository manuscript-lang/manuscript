// conform: tags=ownership
// conform: phase=check
// A trimmed text borrows its receiver: a closure cannot answer one for `map` to store, and a
// function cannot return one of its own local, which dies at the return.
fn of_closure(lines List[String]) List[String] {
	return lines.map(line => line.trim())
}

fn of_local(n Int) String {
	text := f"  a local text that is long enough to be heap allocated {n}  "
	return text.trim()
}

fn main() Void {
	print(of_local(1))
	print(of_closure([" a "])[0])
}
