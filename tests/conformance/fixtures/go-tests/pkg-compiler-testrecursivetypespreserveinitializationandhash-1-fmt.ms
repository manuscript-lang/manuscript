# conform: tags=formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:9 TestRecursiveTypesPreserveInitializationAndHashing
type Node:
    value: Int
    next: Optional[Node]
