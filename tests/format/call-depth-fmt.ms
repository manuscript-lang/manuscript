// conform: tags=closures,control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/call-depth.ms
import expect_equal from "@std/test/test.ms"

type Walker {
	step Int
	limit Int
}

interface Walk {
	fn walk(n Int) Int
}

fn Walker.walk(n Int) Int {
	if n == self.limit {
		return 0
	}
	return 1 + self.walk(n: n + self.step)
}

fn bounded(n Int, limit Int) Int {
	if n == limit {
		return 0
	}
	return 1 + bounded(n: n + 1, limit: limit)
}

test "recursion below the limit runs normally" {
	(bounded(n: 0, limit: 100000) - 100000) | expect_equal(0)?
}

test "method recursion below the limit runs normally" {
	(Walker(step: 1, limit: 100000).walk(n: 0) - 100000) | expect_equal(0)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Walker {
// expect-formatted: \tstep, limit Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Walk {
// expect-formatted: \tfn walk(n Int) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Walker.walk(n Int) Int {
// expect-formatted: \tif n == self.limit {
// expect-formatted: \t\treturn 0
// expect-formatted: \t}
// expect-formatted: \treturn 1 + self.walk(n: n + self.step)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn bounded(n, limit Int) Int {
// expect-formatted: \tif n == limit {
// expect-formatted: \t\treturn 0
// expect-formatted: \t}
// expect-formatted: \treturn 1 + bounded(n: n + 1, limit: limit)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "recursion below the limit runs normally" {
// expect-formatted: \t(bounded(n: 0, limit: 100000) - 100000) | expect_equal(0)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "method recursion below the limit runs normally" {
// expect-formatted: \t(Walker(step: 1, limit: 100000).walk(n: 0) - 100000) | expect_equal(0)?
// expect-formatted: }
