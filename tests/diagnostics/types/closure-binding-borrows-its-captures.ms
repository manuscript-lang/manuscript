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
// expect-error: MS3000 8:5 cannot change `xs` while `size` captures it (closure, at 7:5); finish using `size` before this, or capture a clone: bind `.clone()` of the value first and capture that binding
// expect-error: MS3000 15:5 cannot reassign `n` while `read` captures it (closure, at 14:5); finish using `read` before this, or capture a clone: bind `.clone()` of the value first and capture that binding
