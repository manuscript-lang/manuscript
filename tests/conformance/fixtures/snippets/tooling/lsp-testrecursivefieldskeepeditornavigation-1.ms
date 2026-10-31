# conform: tags=diagnostics,faults,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/recursive_types_test.go:9 TestRecursiveFieldsKeepEditorNavigation
type Node:
    value: Int
    next: Node?

fn read(node: Node) Int:
    return node.next.get().value
