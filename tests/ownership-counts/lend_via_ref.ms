# expect-debug: allocs=42 alloc_bytes=5744
# expect-release: allocs=42 alloc_bytes=5744
# Reading a child through a `ref` result: no copy. The floor that lend_via_clone.ms must reach once clones of unchanged places
# become views.
type Node:
    key: Int
    kids: List[Node]

fn build(depth: Int) Node:
    var kids = List[Node]()
    if depth > 0:
        for i in 0..3:
            kids.append(build(depth - 1))
    return Node(depth, kids)

fn first_kid(n: Node) ref Node?:
    if n.kids.length() == 0:
        return none

    return some(n.kids[0])

fn descend(n: Node, d: Int) Int:
    if d == 0:
        return n.key
    if let k = first_kid(n):
        return descend(k, d - 1)

    return 0

export fn main() Int:
    let t = build(4)
    return descend(t, 3) - 1
