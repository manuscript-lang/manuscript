// conform: tags=control-flow,formatter,generics,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/recursive-interface-bound.ms
import expect_equal from "@std/test/test.ms"

interface Compare[T] {
	fn compare(other T) Int
}

fn compare[T Compare[T]](first T, second T) Int => first.compare(second)

type Key {
	value Int
}

fn Key.compare(other Key) Int => self.value - other.value

test "interface bounds may reference their parameter" {
	expect_equal(compare(Key(7), Key(4)), 3)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: interface Compare[T] {
// expect-formatted: \tfn compare(other T) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn compare[T Compare[T]](first, second T) Int => first.compare(second)
// expect-formatted:
// expect-formatted: type Key {
// expect-formatted: \tvalue Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Key.compare(other Key) Int => self.value - other.value
// expect-formatted:
// expect-formatted: test "interface bounds may reference their parameter" {
// expect-formatted: \texpect_equal(compare(Key(7), Key(4)), 3)?
// expect-formatted: }
