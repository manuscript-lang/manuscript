// conform: tags=control-flow,formatter,interpolation,lists,modules,mutation,optional,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/if-let.ms
import expect_true, fail from "@std/test/test.ms"

fn describe(name String?) String {
	value := name

	if value != null {
		return "Hello, " + value
	} else {
		return "Hello!"
	}
}

fn total(items List[Int?]) Int {
	var sum = 0

	for item in items {
		value := item
		if value != null {
			sum += value
		}
	}

	return sum
}

fn check(value Bool, message String) Void! {
	(value) | expect_true?
}

test "if let unwraps a present optional" {
	value := [4, 5].first()

	if value != null {
		(check(value: value == 4, message: "wrong value")?)
	} else {
		fail(message: "expected some")?
	}
}

test "if let takes else when absent and keeps falsy payloads" {
	(check(value: describe(null) == "Hello!", message: "none")?)
	(check(value: describe("Ada") == "Hello, Ada", message: "some")?)

	items List[Int?] := [1, null, 0, 2]
	(check(value: total(items) == 3, message: "total")?)

	empty List[Int] := []
	value := empty.first()
	if value != null { return fail(message: f"unexpected {value}") }
}

fn parse(text String) Int!Error {
	if text == "" { return error(Error("empty")) }
	return ok(text.length())
}

test "if let unwraps an ok result and takes else on error" {
	if value := parse("abc") {
		(check(value: value == 3, message: "ok value")?)
	} else {
		fail(message: "expected ok")?
	}

	if value := parse("") {
		fail(message: f"unexpected {value}")?
	} else {
		(check(value: true, message: "error branch")?)
	}
}
// expect-format: rewritten
// expect-formatted: import expect_true, fail from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn describe(name String?) String {
// expect-formatted: \tvalue := name
// expect-formatted:
// expect-formatted: \tif value != null {
// expect-formatted: \t\treturn "Hello, " + value
// expect-formatted: \t} else {
// expect-formatted: \t\treturn "Hello!"
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn total(items List[Int?]) Int {
// expect-formatted: \tvar sum = 0
// expect-formatted:
// expect-formatted: \tfor item in items {
// expect-formatted: \t\tvalue := item
// expect-formatted: \t\tif value != null {
// expect-formatted: \t\t\tsum += value
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn sum
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn check(value Bool, message String) Void! {
// expect-formatted: \t(value) | expect_true?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "if let unwraps a present optional" {
// expect-formatted: \tvalue := [4, 5].first()
// expect-formatted:
// expect-formatted: \tif value != null {
// expect-formatted: \t\t(check(value: value == 4, message: "wrong value")?)
// expect-formatted: \t} else {
// expect-formatted: \t\tfail(message: "expected some")?
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "if let takes else when absent and keeps falsy payloads" {
// expect-formatted: \t(check(value: describe(null) == "Hello!", message: "none")?)
// expect-formatted: \t(check(value: describe("Ada") == "Hello, Ada", message: "some")?)
// expect-formatted:
// expect-formatted: \titems List[Int?] := [1, null, 0, 2]
// expect-formatted: \t(check(value: total(items) == 3, message: "total")?)
// expect-formatted:
// expect-formatted: \tempty List[Int] := []
// expect-formatted: \tvalue := empty.first()
// expect-formatted: \tif value != null { return fail(message: f"unexpected {value}") }
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn parse(text String) Int! {
// expect-formatted: \tif text == "" { return error(Error("empty")) }
// expect-formatted: \treturn ok(text.length())
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "if let unwraps an ok result and takes else on error" {
// expect-formatted: \tif value := parse("abc") {
// expect-formatted: \t\t(check(value: value == 3, message: "ok value")?)
// expect-formatted: \t} else {
// expect-formatted: \t\tfail(message: "expected ok")?
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tif value := parse("") {
// expect-formatted: \t\tfail(message: f"unexpected {value}")?
// expect-formatted: \t} else {
// expect-formatted: \t\t(check(value: true, message: "error branch")?)
// expect-formatted: \t}
// expect-formatted: }
