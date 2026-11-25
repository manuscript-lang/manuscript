// conform: tags=diagnostics,formatter,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/recursive_types_test.go:12 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Node {
	next Node?
}

export fn main() Int {
	node := Node(node)
	return 0
}
// expect-error: MS2001 9:18 unknown binding node; declare it with 'node := ...' before use, define 'fn node(...) T { ... }', or import it from a module
