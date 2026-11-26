// conform: tags=closures,control-flow,faults,formatter,interpolation,lists,match,modules,mutation,optional,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/local-closures-keep-semantics.ms
import expect_true from "@std/test/test.ms"

fn bump(factor Int) Int {
	var offset = 10
	offset = 99

	scale := fn(value Int) Int => value * factor + offset
	return scale(value: 2)
}

fn lookup(limit Int) Int {
	find := fn(key Int) Int? {
		if key < limit {
			return (key * 2)
		}
		return null
	}

	var total = 0
	var i = 0

	while i < 5 {
		match find(key: i) {
			found => {
				total += found
			}
			null => {
				total += 100
			}
		}

		i += 1
	}

	return total
}

fn parse(text String) Int!Error {
	guard := fn(number Int) Int!Error {
		if number < 0 {
			return Result[Int, Error].error(Error("negative"))
		}
		return Result[Int, Error].ok(number)
	}

	checked := guard(number: text.length())?
	return Result[Int, Error].ok(checked + 1)
}

fn labels(prefix String) String {
	join := fn(left String, right String) String => f"{prefix}{left}-{right}"
	return join(left: "a", right: "b")
}

fn reordered() Int {
	subtract := fn(left Int, right Int) Int => left - right
	return subtract(right: 2, left: 7)
}

fn passed() List[Int] {
	double := fn(value Int) Int => value * 2
	return [1, 2, 3].map(double)
}

fn nested(n Int) Int {
	inner := fn(x Int) Int => x + 1
	outer := fn(y Int) Int => inner(x: y) * 2
	return outer(y: n)
}

test "local closures" {
	expect_true((bump(factor: 3) == 105))?
	expect_true((lookup(limit: 3) == 0 + 2 + 4 + 100 + 100))?
	expect_true((parse(text: "abc") == Result[Int, Error].ok(4)))?
	expect_true((labels(prefix: ">") == ">a-b"))?
	expect_true((reordered() == 5))?
	expect_true((passed().length() == 3 and passed()[2] == 6))?
	expect_true((nested(n: 4) == 10))?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn bump(factor Int) Int {
// expect-formatted: \tvar offset = 10
// expect-formatted: \toffset = 99
// expect-formatted:
// expect-formatted: \tscale := fn(value Int) Int => value * factor + offset
// expect-formatted: \treturn scale(value: 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn lookup(limit Int) Int {
// expect-formatted: \tfind := fn(key Int) Int? {
// expect-formatted: \t\tif key < limit {
// expect-formatted: \t\t\treturn (key * 2)
// expect-formatted: \t\t}
// expect-formatted: \t\treturn null
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tvar total = 0
// expect-formatted: \tvar i = 0
// expect-formatted:
// expect-formatted: \twhile i < 5 {
// expect-formatted: \t\tmatch find(key: i) {
// expect-formatted: \t\t\tfound => {
// expect-formatted: \t\t\t\ttotal += found
// expect-formatted: \t\t\t}
// expect-formatted: \t\t\tnull => {
// expect-formatted: \t\t\t\ttotal += 100
// expect-formatted: \t\t\t}
// expect-formatted: \t\t}
// expect-formatted:
// expect-formatted: \t\ti += 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn total
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn parse(text String) Int! {
// expect-formatted: \tguard := fn(number Int) Int! {
// expect-formatted: \t\tif number < 0 {
// expect-formatted: \t\t\treturn Result[Int, Error].error(Error("negative"))
// expect-formatted: \t\t}
// expect-formatted: \t\treturn Result[Int, Error].ok(number)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tchecked := guard(number: text.length())?
// expect-formatted: \treturn Result[Int, Error].ok(checked + 1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn labels(prefix String) String {
// expect-formatted: \tjoin := fn(left, right String) String => f"{prefix}{left}-{right}"
// expect-formatted: \treturn join(left: "a", right: "b")
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn reordered() Int {
// expect-formatted: \tsubtract := fn(left, right Int) Int => left - right
// expect-formatted: \treturn subtract(right: 2, left: 7)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn passed() List[Int] {
// expect-formatted: \tdouble := fn(value Int) Int => value * 2
// expect-formatted: \treturn [1, 2, 3].map(double)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn nested(n Int) Int {
// expect-formatted: \tinner := fn(x Int) Int => x + 1
// expect-formatted: \touter := fn(y Int) Int => inner(x: y) * 2
// expect-formatted: \treturn outer(y: n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "local closures" {
// expect-formatted: \texpect_true((bump(factor: 3) == 105))?
// expect-formatted: \texpect_true((lookup(limit: 3) == 0 + 2 + 4 + 100 + 100))?
// expect-formatted: \texpect_true((parse(text: "abc") == Result[Int, Error].ok(4)))?
// expect-formatted: \texpect_true((labels(prefix: ">") == ">a-b"))?
// expect-formatted: \texpect_true((reordered() == 5))?
// expect-formatted: \texpect_true((passed().length() == 3 and passed()[2] == 6))?
// expect-formatted: \texpect_true((nested(n: 4) == 10))?
// expect-formatted: }
