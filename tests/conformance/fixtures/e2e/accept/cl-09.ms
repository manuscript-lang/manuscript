# conform: tags=generics,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-09.ms
from "@std/testing.ms" import expect_equal, expect_false

type Box[T]:
    value: T

def unwrap[T](box: Box[T]) -> T:
    return box.value

def same[T: Equal](left: T, right: T) -> Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](6)
    try expect_equal(unwrap(box), 6)
    try expect_equal(unwrap[Int](box), 6)
    try expect_false(not (same(6, 6)))
