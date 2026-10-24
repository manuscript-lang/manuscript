# conform: tags=alternatives,match,testing,tier-stdlib
# conform: phase=test
# conform: origin=perf: payloadless cases of recursive alternatives share one block
from "@std/testing.ms" import expect_equal

type Tree:
    case Leaf
    case Gap
    case Node(left: Tree, right: Tree)

type Chain:
    case End
    case Link(value: Int, rest: Chain)

def build(depth: Int) -> Tree:
    if depth == 0:
        return Leaf
    if depth == 1:
        return Node(Gap, Leaf)

    return Node(build(depth - 1), build(depth - 2))

def count(tree: Tree) -> Int:
    match tree:
        case Leaf: return 1
        case Gap: return 0
        case Node(left, right): return count(left) + count(right)

def sum(chain: Chain) -> Int:
    match chain:
        case End: return 0
        case Link(value, rest): return value + sum(rest)

test "payloadless cases survive clone, equality and drop":
    let tree = build(10)
    let copy = tree.clone()
    count(copy.clone()) | try expect_equal(expected: count(tree.clone()))
    (copy == tree) | try expect_equal(expected: True)
    (Leaf == Gap) | try expect_equal(expected: False)

test "chains end in a shared block":
    var chain = End
    var i = 0

    while i < 1000:
        chain = Link(i, chain)
        i += 1

    let copy = chain.clone()
    sum(copy) | try expect_equal(expected: 499500)
    sum(chain.clone()) | try expect_equal(expected: 499500)
