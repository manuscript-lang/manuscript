import panic from "@std/faults.ms"

interface Compare[T]:
    fn compare(other: T) -> Int

fn compare[T: Compare[T]](first: T, second: T) -> Int: first.compare(second)

type Key:
    value: Int

impl Compare[Key] for Key:
    fn compare(other: Key) -> Int: self.value - other.value

test "interface bounds may reference their parameter":
    if compare(first: Key(7), second: Key(4)) != 3:
        panic("lost recursive interface bound")
