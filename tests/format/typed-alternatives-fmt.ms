// conform: tags=control-flow,faults,formatter,interpolation,modules,mutation,numbers,optional,parser,stdlib-collections,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/typed-alternatives.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

fn checked(n Int) Int!Error {
	if n < 0 { return error(Error("negative")) }
	return ok(n + 1)
}

fn chain(n Int) Int!Error {
	v := checked(n)?
	return ok(v * 2)
}

fn deeper(n Int) Int!Error {
	a := chain(n)?
	b := chain(a)?
	return ok(a + b)
}

fn expression_try(n Int) Int!Error {
	x := (checked(n)?) + 100
	return ok(x)
}

fn passthrough(n Int) Int!Error {
	return checked(n)
}

fn through_local(n Int) Int!Error {
	r := checked(n)
	return r
}

fn halve(n Int) Int? {
	if n % 2 != 0 { return null }
	return (n / 2)
}

fn word(n Int) String!Error {
	if n == 0 { return error(Error("zero")) }
	return ok(f"w{n}")
}

fn ratio(n Int) Float!Error {
	return ok(1.5)
}

fn nothing(flag Bool) Void!Error {
	if flag { return ok() }
	return error(Error("no"))
}

fn nested(n Int) Int?? {
	if n == 0 { return null }
	return halve(n)
}

fn matched_value(n Int) Int {
	return checked(n).get_or(-1)
}

fn closure_return(n Int) Int!Error {
	y := halve(n)
	if y != null { return ok(y) }

	return error(Error("odd"))
}

fn sum_all(count Int) Int!Error {
	var total = 0

	for i in 0..count {
		v := checked(i)?
		total += v
	}

	return ok(total)
}

test "result matching" {
	v := chain(3).get()
	expect_equal(v, 8)?

	failure := chain(-1)
	expect_false(not failure.is_error())?
	expect_equal(failure.err().message, "negative")?
}

test "chains?" {
	v := deeper(1).get()
	if not (v == 4 + 10) { return fail(f"deeper {v}") }

	deeper_failure := deeper(-5)
	expect_false(not deeper_failure.is_error())?
	expect_equal(deeper_failure.err().message, "negative")?

	x := expression_try(4).get()
	expect_equal(x, 105)?
	expect_false(not expression_try(-4).is_error())?

	total := sum_all(5).get()
	if not (total == 15) { return fail(f"sum {total}") }
}

test "boxed consumers" {
	expect_equal(f"{checked(2)}", f"{passthrough(2)}")?
	expect_equal(checked(2), through_local(2))?
	expect_equal(checked(-2), passthrough(-2))?

	f := checked
	v := f(6).get()
	expect_equal(v, 7)?
	expect_equal(matched_value(3), 4)?
	expect_equal(matched_value(-3), -1)?
}

test "optional and payload kinds" {
	h := halve(8)

	if h != null {
		expect_equal(h, 4)?
	} else {
		return fail("halve none")
	}

	expect_false(halve(7) != null)?

	w := word(3).get()
	expect_equal(w, "w3")?

	r := ratio(1).get()
	expect_equal(r, 1.5)?
	nothing(true).get()

	inner := nested(4)

	if inner != null {
		expect_equal(inner, 2)?
	} else {
		return fail("nested none")
	}

	odd := closure_return(5)
	expect_false(not odd.is_error())?
	expect_equal(odd.err().message, "odd")?

	even := closure_return(6).get()
	expect_equal(even, 3)?
}

test "list at unwrap" {
	items := [10, 20, 30]
	expect_equal(items[0], 10)?
	expect_equal(items[-1], 30)?
	expect_equal(items[1] + items[2], 50)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false, fail from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn checked(n Int) Int! {
// expect-formatted: \tif n < 0 { return error(Error("negative")) }
// expect-formatted: \treturn ok(n + 1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn chain(n Int) Int! {
// expect-formatted: \tv := checked(n)?
// expect-formatted: \treturn ok(v * 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn deeper(n Int) Int! {
// expect-formatted: \ta := chain(n)?
// expect-formatted: \tb := chain(a)?
// expect-formatted: \treturn ok(a + b)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn expression_try(n Int) Int! {
// expect-formatted: \tx := (checked(n)?) + 100
// expect-formatted: \treturn ok(x)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn passthrough(n Int) Int! {
// expect-formatted: \treturn checked(n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn through_local(n Int) Int! {
// expect-formatted: \tr := checked(n)
// expect-formatted: \treturn r
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn halve(n Int) Int? {
// expect-formatted: \tif n % 2 != 0 { return null }
// expect-formatted: \treturn (n / 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn word(n Int) String! {
// expect-formatted: \tif n == 0 { return error(Error("zero")) }
// expect-formatted: \treturn ok(f"w{n}")
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn ratio(n Int) Float! {
// expect-formatted: \treturn ok(1.5)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn nothing(flag Bool) Void! {
// expect-formatted: \tif flag { return ok() }
// expect-formatted: \treturn error(Error("no"))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn nested(n Int) Int?? {
// expect-formatted: \tif n == 0 { return null }
// expect-formatted: \treturn halve(n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn matched_value(n Int) Int {
// expect-formatted: \treturn checked(n).get_or(-1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn closure_return(n Int) Int! {
// expect-formatted: \ty := halve(n)
// expect-formatted: \tif y != null { return ok(y) }
// expect-formatted:
// expect-formatted: \treturn error(Error("odd"))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn sum_all(count Int) Int! {
// expect-formatted: \tvar total = 0
// expect-formatted:
// expect-formatted: \tfor i in 0..count {
// expect-formatted: \t\tv := checked(i)?
// expect-formatted: \t\ttotal += v
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn ok(total)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "result matching" {
// expect-formatted: \tv := chain(3).get()
// expect-formatted: \texpect_equal(v, 8)?
// expect-formatted:
// expect-formatted: \tfailure := chain(-1)
// expect-formatted: \texpect_false(not failure.is_error())?
// expect-formatted: \texpect_equal(failure.err().message, "negative")?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "chains?" {
// expect-formatted: \tv := deeper(1).get()
// expect-formatted: \tif not (v == 4 + 10) { return fail(f"deeper {v}") }
// expect-formatted:
// expect-formatted: \tdeeper_failure := deeper(-5)
// expect-formatted: \texpect_false(not deeper_failure.is_error())?
// expect-formatted: \texpect_equal(deeper_failure.err().message, "negative")?
// expect-formatted:
// expect-formatted: \tx := expression_try(4).get()
// expect-formatted: \texpect_equal(x, 105)?
// expect-formatted: \texpect_false(not expression_try(-4).is_error())?
// expect-formatted:
// expect-formatted: \ttotal := sum_all(5).get()
// expect-formatted: \tif not (total == 15) { return fail(f"sum {total}") }
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "boxed consumers" {
// expect-formatted: \texpect_equal(f"{checked(2)}", f"{passthrough(2)}")?
// expect-formatted: \texpect_equal(checked(2), through_local(2))?
// expect-formatted: \texpect_equal(checked(-2), passthrough(-2))?
// expect-formatted:
// expect-formatted: \tf := checked
// expect-formatted: \tv := f(6).get()
// expect-formatted: \texpect_equal(v, 7)?
// expect-formatted: \texpect_equal(matched_value(3), 4)?
// expect-formatted: \texpect_equal(matched_value(-3), -1)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "optional and payload kinds" {
// expect-formatted: \th := halve(8)
// expect-formatted:
// expect-formatted: \tif h != null {
// expect-formatted: \t\texpect_equal(h, 4)?
// expect-formatted: \t} else {
// expect-formatted: \t\treturn fail("halve none")
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \texpect_false(halve(7) != null)?
// expect-formatted:
// expect-formatted: \tw := word(3).get()
// expect-formatted: \texpect_equal(w, "w3")?
// expect-formatted:
// expect-formatted: \tr := ratio(1).get()
// expect-formatted: \texpect_equal(r, 1.5)?
// expect-formatted: \tnothing(true).get()
// expect-formatted:
// expect-formatted: \tinner := nested(4)
// expect-formatted:
// expect-formatted: \tif inner != null {
// expect-formatted: \t\texpect_equal(inner, 2)?
// expect-formatted: \t} else {
// expect-formatted: \t\treturn fail("nested none")
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \todd := closure_return(5)
// expect-formatted: \texpect_false(not odd.is_error())?
// expect-formatted: \texpect_equal(odd.err().message, "odd")?
// expect-formatted:
// expect-formatted: \teven := closure_return(6).get()
// expect-formatted: \texpect_equal(even, 3)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "list at unwrap" {
// expect-formatted: \titems := [10, 20, 30]
// expect-formatted: \texpect_equal(items[0], 10)?
// expect-formatted: \texpect_equal(items[-1], 30)?
// expect-formatted: \texpect_equal(items[1] + items[2], 50)?
// expect-formatted: }
