from "@std/test.ms" import expect_equal

# Each rebuild hands the old value to a callee that stores it. A callee that copies its
# argument makes the loop quadratic, so these sizes finish only when the argument moves.
type Node:
    val: Int
    kids: List[Node]

def wrap(n: Node, i: Int) -> Node:
    return Node(i, [n])

impl Node:
    def up(i: Int) -> Node:
        return Node(i, [self])

test "a consumed function argument moves":
    var nd = Node(0, List[Node]())
    for i in 0..30000:
        nd = wrap(nd, i)
    nd.val | try expect_equal(29999)

test "a consumed receiver moves":
    var nd = Node(0, List[Node]())
    for i in 0..30000:
        nd = nd.up(i)
    nd.val | try expect_equal(29999)
