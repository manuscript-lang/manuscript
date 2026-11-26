// conform: tags=closures,control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/try-statement.ms
import expect_equal from "@std/test/test.ms"

fn parse(n Int) Int!Error {
	if n < 0 {
		return error(Error("neg"))
	}
	return ok(n)
}

fn bound(n Int) Int!Error {
	v := parse(n)?
	return ok(v + 1)
}

fn reassigned(n Int) Int!Error {
	var total = 1
	total = parse(n)?
	return ok(total * 2)
}

fn check(n Int) Void!Error {
	if n < 0 {
		return error(Error("neg"))
	}
}

fn discarded(n Int) Int!Error {
	check(n)?
	return ok(7)
}

fn code(r Int!Error) Int {
	return r.clone().get_or(-1)
}

fn nested(n Int) Int!Error {
	return ok((parse(n)?) + (parse(n - 5)?))
}

fn chained(n Int) Int!Error {
	a := bound(n)?
	b := reassigned(a - 10)?
	return ok(b)
}

fn in_loop(values List[Int]) Int!Error {
	var sum = 0
	for v in values {
		sum += parse(v)?
	}
	return ok(sum)
}

fn in_lambda(n Int) Int!Error {
	inner := fn() Int!Error {
		v := parse(n)?
		return ok(v * 10)
	}

	r := inner()?
	return ok(r + 1)
}

test "statement returns? the error and binds the value" {
	expect_equal(code(bound(4)), 5)?
	expect_equal(code(bound(-1)), -1)?
	expect_equal(code(reassigned(3)), 6)?
	expect_equal(code(reassigned(-2)), -1)?
	expect_equal(code(discarded(1)), 7)?
	expect_equal(code(discarded(-1)), -1)?
}

test "nested? in expressions and chains still propagates" {
	expect_equal(code(nested(6)), 7)?
	expect_equal(code(nested(2)), -1)?
	expect_equal(code(chained(12)), 6)?
	expect_equal(code(chained(3)), -1)?
}

test "in? loops and lambdas" {
	expect_equal(code(in_loop([1, 2, 3])), 6)?
	expect_equal(code(in_loop([1, -2, 3])), -1)?
	expect_equal(code(in_lambda(2)), 21)?
	expect_equal(code(in_lambda(-2)), -1)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn parse(n Int) Int! {
// expect-formatted: \tif n < 0 {
// expect-formatted: \t\treturn error(Error("neg"))
// expect-formatted: \t}
// expect-formatted: \treturn ok(n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn bound(n Int) Int! {
// expect-formatted: \tv := parse(n)?
// expect-formatted: \treturn ok(v + 1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn reassigned(n Int) Int! {
// expect-formatted: \tvar total = 1
// expect-formatted: \ttotal = parse(n)?
// expect-formatted: \treturn ok(total * 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn check(n Int) Void! {
// expect-formatted: \tif n < 0 {
// expect-formatted: \t\treturn error(Error("neg"))
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn discarded(n Int) Int! {
// expect-formatted: \tcheck(n)?
// expect-formatted: \treturn ok(7)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn code(r Int!) Int {
// expect-formatted: \treturn r.clone().get_or(-1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn nested(n Int) Int! {
// expect-formatted: \treturn ok((parse(n)?) + (parse(n - 5)?))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn chained(n Int) Int! {
// expect-formatted: \ta := bound(n)?
// expect-formatted: \tb := reassigned(a - 10)?
// expect-formatted: \treturn ok(b)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn in_loop(values List[Int]) Int! {
// expect-formatted: \tvar sum = 0
// expect-formatted: \tfor v in values {
// expect-formatted: \t\tsum += parse(v)?
// expect-formatted: \t}
// expect-formatted: \treturn ok(sum)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn in_lambda(n Int) Int! {
// expect-formatted: \tinner := fn() Int! {
// expect-formatted: \t\tv := parse(n)?
// expect-formatted: \t\treturn ok(v * 10)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tr := inner()?
// expect-formatted: \treturn ok(r + 1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "statement returns? the error and binds the value" {
// expect-formatted: \texpect_equal(code(bound(4)), 5)?
// expect-formatted: \texpect_equal(code(bound(-1)), -1)?
// expect-formatted: \texpect_equal(code(reassigned(3)), 6)?
// expect-formatted: \texpect_equal(code(reassigned(-2)), -1)?
// expect-formatted: \texpect_equal(code(discarded(1)), 7)?
// expect-formatted: \texpect_equal(code(discarded(-1)), -1)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "nested? in expressions and chains still propagates" {
// expect-formatted: \texpect_equal(code(nested(6)), 7)?
// expect-formatted: \texpect_equal(code(nested(2)), -1)?
// expect-formatted: \texpect_equal(code(chained(12)), 6)?
// expect-formatted: \texpect_equal(code(chained(3)), -1)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "in? loops and lambdas" {
// expect-formatted: \texpect_equal(code(in_loop([1, 2, 3])), 6)?
// expect-formatted: \texpect_equal(code(in_loop([1, -2, 3])), -1)?
// expect-formatted: \texpect_equal(code(in_lambda(2)), 21)?
// expect-formatted: \texpect_equal(code(in_lambda(-2)), -1)?
// expect-formatted: }
