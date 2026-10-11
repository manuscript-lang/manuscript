import List from "@std/collections.ms"

type Tree[T: Shareable]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](value: 1, children: [])
    let root = Tree[Int](value: 2, children: [leaf])
    assert root.value == 2
