// conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=documentation/learn/testing.md:13
import expect_equal from "@std/test/test.ms"

fn add(a Int, b Int) Int {
	return a + b
}

test "addition" {
	expect_equal(add(1, 2), 3)?
}

test "zero is unchanged" {
	expect_equal(add(0, 7), 7)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn add(a, b Int) Int {
// expect-formatted: \treturn a + b
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "addition" {
// expect-formatted: \texpect_equal(add(1, 2), 3)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "zero is unchanged" {
// expect-formatted: \texpect_equal(add(0, 7), 7)?
// expect-formatted: }
