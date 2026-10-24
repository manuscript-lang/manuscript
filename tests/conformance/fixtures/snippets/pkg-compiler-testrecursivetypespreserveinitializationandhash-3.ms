# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:12 TestRecursiveTypesPreserveInitializationAndHashing
def f() -> Unit:
    let node = Node(value: 1)
