// conform: tags=closures,control-flow,faults,formatter,lists,modules,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/pipe-flow.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn parse(text String) Int!Error {
	if text == "-" {
		return error(Error("n"))
	}
	if text == "big" {
		return error(Error("big"))
	}

	return ok(text.length())
}

fn double(n Int) Int => n * 2

fn add(n Int, by Int) Int => n + by

fn check(n Int) Int!Error {
	if n > 100 {
		return error(Error("big"))
	}
	return ok(n)
}

fn flow(text String) Int!Error {
	n := parse(text)?
		| double
		| add(3)
		| check?
	return ok(n)
}

fn bare(text String) Int!Error {
	return ok(parse(text)? | double | check?)
}

fn describe(text String) String!Error {
	label := (
		parse(text)?
		| check?
		| add(1)
		| .to_string()
	)
	return ok(label)
}

fn order(var log List[String]) Int {
	return (
		trace(log, "a")
		| add(trace(log, "b"))
		| double
	)
}

fn trace(var log List[String], move name String) Int {
	log.append(name)
	return 1
}

fn code(r Int!Error) Int {
	if v := r {
		return v
	}
	return 0 - r.err().message.length()
}

test "pipe steps call functions with the value first" {
	expect_equal(code(flow("abc")), 9)?
	expect_equal(code(flow("-")), -1)?
	expect_equal(code(flow("big")), -3)?
}

test "bare unwraps? the value so far" {
	expect_equal(bare("abc").get(), 6)?
	expect_equal(code(bare("-")), -1)?
}

test "pipe passes a Result through a step without try" {
	r := parse("abcd") | .map(fn(value Int) Int => value * 2)
	expect_equal(r.get(), 8)?
}

test "leading dot after a step applies to its result" {
	expect_equal(describe("xy").get(), "3")?
}

test "head is evaluated before step arguments" {
	var log List[String] = []
	expect_equal(order(log), 4)?
	expect_false(log[0] != "a" or log[1] != "b")?
}

test "dot steps call methods on the value" {
	size := "abc" | .length() | double
	expect_equal(size, 6)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn parse(text String) Int! {
// expect-formatted: \tif text == "-" {
// expect-formatted: \t\treturn error(Error("n"))
// expect-formatted: \t}
// expect-formatted: \tif text == "big" {
// expect-formatted: \t\treturn error(Error("big"))
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn ok(text.length())
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn double(n Int) Int => n * 2
// expect-formatted:
// expect-formatted: fn add(n, by Int) Int => n + by
// expect-formatted:
// expect-formatted: fn check(n Int) Int! {
// expect-formatted: \tif n > 100 {
// expect-formatted: \t\treturn error(Error("big"))
// expect-formatted: \t}
// expect-formatted: \treturn ok(n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn flow(text String) Int! {
// expect-formatted: \tn := parse(text)?
// expect-formatted: \t\t| double
// expect-formatted: \t\t| add(3)
// expect-formatted: \t\t| check?
// expect-formatted: \treturn ok(n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn bare(text String) Int! {
// expect-formatted: \treturn ok(parse(text)? | double | check?)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn describe(text String) String! {
// expect-formatted: \tlabel := (
// expect-formatted: \t\tparse(text)?
// expect-formatted: \t\t| check?
// expect-formatted: \t\t| add(1)
// expect-formatted: \t\t| .to_string()
// expect-formatted: \t)
// expect-formatted: \treturn ok(label)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn order(var log List[String]) Int {
// expect-formatted: \treturn (
// expect-formatted: \t\ttrace(log, "a")
// expect-formatted: \t\t| add(trace(log, "b"))
// expect-formatted: \t\t| double
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn trace(var log List[String], move name String) Int {
// expect-formatted: \tlog.append(name)
// expect-formatted: \treturn 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn code(r Int!) Int {
// expect-formatted: \tif v := r {
// expect-formatted: \t\treturn v
// expect-formatted: \t}
// expect-formatted: \treturn 0 - r.err().message.length()
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "pipe steps call functions with the value first" {
// expect-formatted: \texpect_equal(code(flow("abc")), 9)?
// expect-formatted: \texpect_equal(code(flow("-")), -1)?
// expect-formatted: \texpect_equal(code(flow("big")), -3)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "bare unwraps? the value so far" {
// expect-formatted: \texpect_equal(bare("abc").get(), 6)?
// expect-formatted: \texpect_equal(code(bare("-")), -1)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "pipe passes a Result through a step without try" {
// expect-formatted: \tr := parse("abcd") | .map(fn(value Int) Int => value * 2)
// expect-formatted: \texpect_equal(r.get(), 8)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "leading dot after a step applies to its result" {
// expect-formatted: \texpect_equal(describe("xy").get(), "3")?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "head is evaluated before step arguments" {
// expect-formatted: \tvar log List[String] = []
// expect-formatted: \texpect_equal(order(log), 4)?
// expect-formatted: \texpect_false(log[0] != "a" or log[1] != "b")?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "dot steps call methods on the value" {
// expect-formatted: \tsize := "abc" | .length() | double
// expect-formatted: \texpect_equal(size, 6)?
// expect-formatted: }
