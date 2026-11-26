// conform: tags=formatter,generics,modules,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/cl-09.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Box[T] {
	value T
}

fn unwrap[T](hold box Box[T]) &T {
	return box.value
}

fn same[T Equal](left T, right T) Bool {
	return left == right
}

test "generic argument inference" {
	box := Box[Int](6)
	expect_equal(unwrap(box), 6)?
	expect_equal(unwrap[Int](box), 6)?
	expect_false(not (same(6, 6)))?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Box[T] {
// expect-formatted: \tvalue T
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn unwrap[T](hold box Box[T]) &T {
// expect-formatted: \treturn box.value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn same[T Equal](left, right T) Bool {
// expect-formatted: \treturn left == right
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "generic argument inference" {
// expect-formatted: \tbox := Box[Int](6)
// expect-formatted: \texpect_equal(unwrap(box), 6)?
// expect-formatted: \texpect_equal(unwrap[Int](box), 6)?
// expect-formatted: \texpect_false(not (same(6, 6)))?
// expect-formatted: }
