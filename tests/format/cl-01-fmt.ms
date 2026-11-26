// conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/cl-01.ms
import expect_equal from "@std/test/test.ms"

fn subtract(amount Int, deduction Int) Int {
	return amount - deduction
}

test "named multiline call" {
	remaining := subtract(deduction: 2, amount: 9)
	expect_equal(remaining, 7)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn subtract(amount, deduction Int) Int {
// expect-formatted: \treturn amount - deduction
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "named multiline call" {
// expect-formatted: \tremaining := subtract(deduction: 2, amount: 9)
// expect-formatted: \texpect_equal(remaining, 7)?
// expect-formatted: }
