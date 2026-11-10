// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/recursive_types_test.go:12 TestRecursiveTypesPreserveInitializationAndHashing
fn f() Unit:
    node := Node(value: 1)
