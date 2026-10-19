# conform: tags=aliasing,control-flow,faults,modules,optional,records,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=documentation/core-language/types/records.md:120
import panic from "@std/faults.ms"

type Node:
    value: Int
    next: Optional[Node]

test "recursive links":
    let node = Node(value: 1, next: none)
    node.next = some(node)
    let copy = node.clone()
    copy.next.get().value = 2
    if node.value != 2 or copy.value != 1:
        panic("cloning must retain nested references")
