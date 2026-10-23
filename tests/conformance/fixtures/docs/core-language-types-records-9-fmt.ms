# conform: tags=control-flow,faults,formatter,modules,optional,parser,records,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:120
import panic from "@std/core.ms"

type Node:
    value: Int
    next: Optional[Node]

test "recursive links":
    var node = Node(value: 1, next: none)
    node.next = some(Node(value: 5, next: none))

    var copy = node.clone()
    copy.next = some(Node(value: 2, next: none))
    if node.next.get().value != 5 or copy.next.get().value != 2:
        panic("clones must be independent")
