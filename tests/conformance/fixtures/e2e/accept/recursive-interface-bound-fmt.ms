# conform: tags=control-flow,formatter,generics,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/recursive-interface-bound.ms
import expect_equal from "@std/test/test.ms"

interface Compare[T]:
    fn compare(other: T) Int

fn compare[T: Compare[T]](first: T, second: T) Int: first.compare(second)

type Key:
    value: Int

impl Compare[Key] for Key:
    fn compare(other: Key) Int: self.value - other.value

test "interface bounds may reference their parameter":
    try expect_equal(compare(Key(7), Key(4)), 3)
