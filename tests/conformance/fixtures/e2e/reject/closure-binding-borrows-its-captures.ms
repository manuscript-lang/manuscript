// conform: tags=closures,mutation,diagnostics,tier-core
// conform: phase=check
// A closure kept in a binding borrows what it captures until the binding is last used: the captured list cannot
// change, and a captured Int cannot be reassigned, while the closure is still called.
fn count_after_append() Int {
	var xs = [1, 2, 3]
	size := () => xs.length()
	xs.append(4)
	return size()
}

fn read_after_assign() Int {
	var n = 1
	read := () => n
	n = 5
	return read()
}

export fn main() Int {
	return count_after_append() + read_after_assign()
}
