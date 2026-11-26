// conform: tags=diagnostics
// conform: phase=check
type Node {
	next Node?
}

export fn main() Int {
	node := Node(null)
	node.next = node
	return node.hash()
}
// expect-error: MS2001 10:17 unknown or ambiguous member hash on Node; available: next
