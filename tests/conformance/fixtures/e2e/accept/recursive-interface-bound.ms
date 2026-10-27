# conform: tags=control-flow,generics,interfaces,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/recursive-interface-bound.ms
from "@std/test.ms" import expect_equal

interface Compare[T]:
    def compare(other: T) -> Int

def compare[T: Compare[T]](first: T, second: T) -> Int: first.compare(second)

type Key:
    value: Int

impl Compare[Key] for Key:
    def compare(other: Key) -> Int: self.value - other.value

test "interface bounds may reference their parameter":
    try expect_equal(compare(Key(7), Key(4)), 3)
