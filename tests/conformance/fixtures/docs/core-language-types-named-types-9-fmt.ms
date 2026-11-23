// conform: tags=control-flow,faults,formatter,modules,optional,parser,records,stdlib-faults,testing,tier-stdlib
// conform: phase=parse
// conform: origin=documentation/core-language/types/named-types.md:120
import panic from "@std/core.ms"

type Node:
    value: Int
    next: Node?

test "recursive links":
    var node = Node(value: 1, next: null)
    node.next = Node(value: 5, next: null)

    var copy = node.clone()
    copy.next = Node(value: 2, next: null)
    if node.next.get().value != 5 or copy.next.get().value != 2:
        panic("clones must be independent")
