// conform: tags=diagnostics
// conform: phase=check
type Node:
    value: Int
    next: Node?
fn read(node: Node) Int:
    return node.next.get().value
