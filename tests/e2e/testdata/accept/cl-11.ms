from "@std/test.ms" import expect_equal

type Tree[T]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](1, [])
    let root = Tree[Int](2, [leaf])
    try expect_equal(root.value, 2)
