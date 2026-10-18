import panic from "@std/faults.ms"

type Tree[T]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](1, [])
    let root = Tree[Int](2, [leaf])
    if not (root.value == 2):
        return panic("check failed")
