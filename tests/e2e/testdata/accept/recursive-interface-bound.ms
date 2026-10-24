from "@std/testing.ms" import expect_equal

interface Compare[T]:
    def compare(other: T) -> Int

def compare[T: Compare[T]](first: T, second: T) -> Int: first.compare(second)

type Key:
    value: Int

impl Compare[Key] for Key:
    def compare(other: Key) -> Int: self.value - other.value

test "interface bounds may reference their parameter":
    try expect_equal(compare(Key(7), Key(4)), 3)
