// conform: tags=diagnostics,optional,records,tier-core
// conform: phase=check
// conform: origin=tests/e2e/recursive_types_test.go:13 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Node {
	next Node?
}

export fn main() Int {
	node := Node(null)
	node.next = node
	return node.hash()
}
// expect-error: MS2001 11:17 unknown or ambiguous member hash on Node; available: next
