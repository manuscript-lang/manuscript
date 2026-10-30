# conform: tags=diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/recursive_types_test.go:13 TestRecursiveTypesRejectUnsafeConstructionAndHashing
type Node:
    next: Node?

export fn main() Int:
    let node = Node(none)
    node.next = some(node)
    return node.hash()
