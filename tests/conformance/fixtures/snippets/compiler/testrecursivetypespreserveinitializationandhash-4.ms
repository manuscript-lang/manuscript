# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:13 TestRecursiveTypesPreserveInitializationAndHashing
fn f() Unit:
    let node = Node(value: 1, next: "wrong")
