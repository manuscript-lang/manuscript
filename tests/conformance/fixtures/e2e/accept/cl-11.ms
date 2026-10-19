# conform: tags=lists,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-11.ms
import {expect_equal} from "@std/testing.ms"

type Tree[T]:
    value: T
    children: List[Tree[T]]

test "recursive immutable collection":
    let leaf = Tree[Int](1, [])
    let root = Tree[Int](2, [leaf])
    try expect_equal(root.value, 2)
