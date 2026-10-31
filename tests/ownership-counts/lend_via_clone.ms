# expect-debug: allocs=60 alloc_bytes=7472
# expect-release: allocs=60 alloc_bytes=7472
# Reading a child through a function that returns an owned clone. The `ref` variant in lend_via_ref.ms is the floor that
# guaranteed copy elision must reach for this program before `ref` can be removed.
type Node:
    key: Int
    kids: List[Node]

fn build(depth: Int) Node:
    var kids = List[Node]()
    if depth > 0:
        for i in 0..3:
            kids.append(build(depth - 1))
    return Node(depth, kids)

fn first_kid(n: Node) Node?:
    if n.kids.length() == 0:
        return none

    return n.kids[0].clone()

fn descend(n: Node, d: Int) Int:
    if d == 0:
        return n.key
    if let k = first_kid(n):
        return descend(k, d - 1)

    return 0

export fn main() Int:
    let t = build(4)
    return descend(t, 3) - 1
