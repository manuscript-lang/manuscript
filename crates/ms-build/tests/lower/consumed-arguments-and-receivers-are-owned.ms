# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "fn @wrap(%0: own Node"
# expect-mir: "fn @Node.up(%0: own Node"
type Node:
    val: Int
    kids: List[Node]

fn wrap(n: Node, i: Int) Node:
    return Node(i, [n])

impl Node:
    fn up(i: Int) Node:
        return Node(i, [self])

export fn main() Int:
    var nd = Node(0, List[Node]())
    nd = wrap(nd, 1)
    nd = nd.up(2)
    return nd.val
