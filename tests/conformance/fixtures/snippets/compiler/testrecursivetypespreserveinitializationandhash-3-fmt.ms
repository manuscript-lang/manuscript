// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:12 TestRecursiveTypesPreserveInitializationAndHashing
fn f() Void {
	node := Node(value: 1)
}
