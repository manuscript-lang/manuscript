import {expect_equal} from "@std/testing.ms"

type Tree[T]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](value: 1, children: [])
    let root = Tree[Int](value: 2, children: [leaf])
    root.value | try expect_equal(expected: 2)
