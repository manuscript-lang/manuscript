# conform: tags=alternatives,match,testing,tier-stdlib
# conform: phase=test
# conform: origin=perf: payloadless cases of recursive alternatives share one block
import {expect_equal} from "@std/testing.ms"

type Tree:
    case Leaf
    case Gap
    case Node(left: Tree, right: Tree)

type Chain:
    case End
    case Link(value: Int, rest: Chain)

fn build(depth: Int) Tree:
    if depth == 0:
        return Leaf
    if depth == 1:
        return Node(Gap, Leaf)

    return Node(build(depth - 1), build(depth - 2))

fn count(tree: Tree) Int:
    match tree:
        Leaf: return 1
        Gap: return 0
        Node(left, right): return count(left) + count(right)

fn sum(chain: Chain) Int:
    match chain:
        End: return 0
        Link(value, rest): return value + sum(rest)

test "payloadless cases survive clone, equality and drop":
    let tree = build(10)
    let copy = tree.clone()
    count(copy.clone()) | try expect_equal(expected: count(tree.clone()))
    (copy == tree) | try expect_equal(expected: true)
    (Leaf == Gap) | try expect_equal(expected: false)

test "chains end in a shared block":
    var chain = End
    var i = 0

    while i < 1000:
        chain = Link(i, chain)
        i += 1

    let copy = chain.clone()
    sum(copy) | try expect_equal(expected: 499500)
    sum(chain.clone()) | try expect_equal(expected: 499500)
