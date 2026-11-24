// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:13 TestRecursiveTypesPreserveInitializationAndHashing
fn f() Void {
	node := Node(value: 1, next: "wrong")
}
