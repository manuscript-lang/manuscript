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
