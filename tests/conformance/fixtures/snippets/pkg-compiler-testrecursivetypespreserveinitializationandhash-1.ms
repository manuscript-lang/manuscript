# conform: tags=diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:9 TestRecursiveTypesPreserveInitializationAndHashing
type Node:
    value: Int
    next: Optional[Node]
