// conform: tags=closures,control-flow,formatter,interpolation,match,modules,mutation,optional,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/typed-alternative-lets-keep-semantics.ms
import expect_true from "@std/test/test.ms"

fn halve(n Int) Int? {
	if n % 2 != 0 {
		return null
	}
	return (n / 2)
}

fn parse(n Int) Int!Error {
	if n < 0 {
		return error(cause: Error("negative"))
	}
	return ok(value: n)
}

fn matched(n Int) Int {
	found := halve(n: n)

	match found {
		v => {
			return v
		}
		null => {
			return 0 - 1
		}
	}
}

fn twice(n Int) Int {
	found := halve(n: n)
	var total = 0

	match found {
		v => {
			total += v
		}
		null => {
			total += 100
		}
	}

	match found {
		v => {
			total += v
		}
		null => {
			total += 1000
		}
	}

	return total
}

fn results(n Int) String {
	parsed := parse(n: n)

	match parsed {
		ok(v) => {
			return f"ok {v}"
		}
		error(cause) => {
			return cause.message
		}
	}
}

fn formatted(n Int) String {
	found := halve(n: n)
	return f"{found}"
}

fn captured(n Int) Int {
	found := halve(n: n)
	read := fn() Int {
		match found {
			v => {
				return v
			}
			null => {
				return 0 - 1
			}
		}
	}
	return read()
}

test "typed alternative lets" {
	expect_true((matched(n: 8) == 4))?
	expect_true((matched(n: 7) == 0 - 1))?
	expect_true((twice(n: 8) == 8))?
	expect_true((twice(n: 7) == 1100))?
	expect_true((results(n: 3) == "ok 3"))?
	expect_true((results(n: 0 - 3) == "negative"))?
	expect_true((formatted(n: 8) == formatted(n: 8)))?
	expect_true((captured(n: 8) == 4))?
	expect_true((captured(n: 7) == 0 - 1))?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn halve(n Int) Int? {
// expect-formatted: \tif n % 2 != 0 {
// expect-formatted: \t\treturn null
// expect-formatted: \t}
// expect-formatted: \treturn (n / 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn parse(n Int) Int! {
// expect-formatted: \tif n < 0 {
// expect-formatted: \t\treturn error(cause: Error("negative"))
// expect-formatted: \t}
// expect-formatted: \treturn ok(value: n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn matched(n Int) Int {
// expect-formatted: \tfound := halve(n: n)
// expect-formatted:
// expect-formatted: \tmatch found {
// expect-formatted: \t\tv => {
// expect-formatted: \t\t\treturn v
// expect-formatted: \t\t}
// expect-formatted: \t\tnull => {
// expect-formatted: \t\t\treturn 0 - 1
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn twice(n Int) Int {
// expect-formatted: \tfound := halve(n: n)
// expect-formatted: \tvar total = 0
// expect-formatted:
// expect-formatted: \tmatch found {
// expect-formatted: \t\tv => {
// expect-formatted: \t\t\ttotal += v
// expect-formatted: \t\t}
// expect-formatted: \t\tnull => {
// expect-formatted: \t\t\ttotal += 100
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch found {
// expect-formatted: \t\tv => {
// expect-formatted: \t\t\ttotal += v
// expect-formatted: \t\t}
// expect-formatted: \t\tnull => {
// expect-formatted: \t\t\ttotal += 1000
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn total
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn results(n Int) String {
// expect-formatted: \tparsed := parse(n: n)
// expect-formatted:
// expect-formatted: \tmatch parsed {
// expect-formatted: \t\tok(v) => {
// expect-formatted: \t\t\treturn f"ok {v}"
// expect-formatted: \t\t}
// expect-formatted: \t\terror(cause) => {
// expect-formatted: \t\t\treturn cause.message
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn formatted(n Int) String {
// expect-formatted: \tfound := halve(n: n)
// expect-formatted: \treturn f"{found}"
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn captured(n Int) Int {
// expect-formatted: \tfound := halve(n: n)
// expect-formatted: \tread := fn() Int {
// expect-formatted: \t\tmatch found {
// expect-formatted: \t\t\tv => {
// expect-formatted: \t\t\t\treturn v
// expect-formatted: \t\t\t}
// expect-formatted: \t\t\tnull => {
// expect-formatted: \t\t\t\treturn 0 - 1
// expect-formatted: \t\t\t}
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: \treturn read()
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "typed alternative lets" {
// expect-formatted: \texpect_true((matched(n: 8) == 4))?
// expect-formatted: \texpect_true((matched(n: 7) == 0 - 1))?
// expect-formatted: \texpect_true((twice(n: 8) == 8))?
// expect-formatted: \texpect_true((twice(n: 7) == 1100))?
// expect-formatted: \texpect_true((results(n: 3) == "ok 3"))?
// expect-formatted: \texpect_true((results(n: 0 - 3) == "negative"))?
// expect-formatted: \texpect_true((formatted(n: 8) == formatted(n: 8)))?
// expect-formatted: \texpect_true((captured(n: 8) == 4))?
// expect-formatted: \texpect_true((captured(n: 7) == 0 - 1))?
// expect-formatted: }
