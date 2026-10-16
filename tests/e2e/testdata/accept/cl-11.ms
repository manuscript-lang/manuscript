import panic from "@std/faults.ms"

type Tree[T]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](value: 1, children: [])
    let root = Tree[Int](value: 2, children: [leaf])
    if not (root.value == 2):
        return panic(message: "check failed")
