// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/recursive_types_test.go:13 TestRecursiveTypesPreserveInitializationAndHashing
fn f() Void {
	node := Node(value: 1, next: "wrong")
}
// expect-error: MS2001 5:13 unknown binding Node; declare it with 'Node := ...' before use, define 'fn Node(...) T { ... }', or import it from a module
