# conform: tags=diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/recursive_types_test.go:12 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Node:
    next: Optional[Node]

export fn main() Int:
    let node = Node(node)
    return 0
