# conform: tags=faults,formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/recursive_types_test.go:9 TestRecursiveFieldsKeepEditorNavigation
type Node:
    value: Int
    next: Optional[Node]

fn read(node: Node) Int:
    return node.next.get().value
