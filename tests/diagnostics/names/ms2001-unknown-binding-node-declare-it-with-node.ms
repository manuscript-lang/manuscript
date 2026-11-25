// conform: tags=diagnostics
// conform: phase=check
type Node {
	next Node?
}

fn main() Void {
	node := Node(node)
}
// expect-error: MS2001 8:18 unknown binding node; declare it with 'node := ...' before use, define 'fn node(...) T { ... }', or import it from a module
