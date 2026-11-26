// conform: tags=closures,control-flow,formatter,generics,interfaces,interpolation,match,modules,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/runtime-3.ms
import expect_equal, expect_true, fail from "@std/test/test.ms"

fn identity[T](hold value T) &T {
	return value
}

fn probe() Void! {
	first := fn() Int!Error {
		return ok(3)
	}
	second := () => {
		return true
	}
	number := identity(first)()
	flag := second()
	(flag) | expect_true?

	match number {
		ok(value) => {
			expect_equal(value, 3)?
		}
		error(_) => {
			return fail(message: "Unexpected case")
		}
	}
}

test "typed callback helper" {
	match probe() {
		ok(_) => {
			_completed := void
		}
		error(_) => {
			return fail(message: "Unexpected case")
		}
	}
}

type Code {
	number Int
}

fn describe(outcome Int!Code) Int!Error {
	match outcome {
		ok(value) => {
			return ok(value)
		}
		error(cause) => {
			return error(Error(f"Error {cause.number}"))
		}
	}
}

test "explicit error conversion" {
	failed Int!Code := error(Code(7))
	expected Int!Error := error(Error("Error 7"))
	describe(outcome: failed) | expect_equal(expected)?

	succeeded Int!Code := ok(3)
	unchanged Int!Error := ok(3)
	describe(outcome: succeeded) | expect_equal(unchanged)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_true, fail from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn identity[T](hold value T) &T {
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn probe() Void! {
// expect-formatted: \tfirst := fn() Int! {
// expect-formatted: \t\treturn ok(3)
// expect-formatted: \t}
// expect-formatted: \tsecond := () => {
// expect-formatted: \t\treturn true
// expect-formatted: \t}
// expect-formatted: \tnumber := identity(first)()
// expect-formatted: \tflag := second()
// expect-formatted: \t(flag) | expect_true?
// expect-formatted:
// expect-formatted: \tmatch number {
// expect-formatted: \t\tok(value) => {
// expect-formatted: \t\t\texpect_equal(value, 3)?
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "Unexpected case")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "typed callback helper" {
// expect-formatted: \tmatch probe() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_completed := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "Unexpected case")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Code {
// expect-formatted: \tnumber Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn describe(outcome Int!Code) Int! {
// expect-formatted: \tmatch outcome {
// expect-formatted: \t\tok(value) => {
// expect-formatted: \t\t\treturn ok(value)
// expect-formatted: \t\t}
// expect-formatted: \t\terror(cause) => {
// expect-formatted: \t\t\treturn error(Error(f"Error {cause.number}"))
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "explicit error conversion" {
// expect-formatted: \tfailed Int!Code := error(Code(7))
// expect-formatted: \texpected Int! := error(Error("Error 7"))
// expect-formatted: \tdescribe(outcome: failed) | expect_equal(expected)?
// expect-formatted:
// expect-formatted: \tsucceeded Int!Code := ok(3)
// expect-formatted: \tunchanged Int! := ok(3)
// expect-formatted: \tdescribe(outcome: succeeded) | expect_equal(unchanged)?
// expect-formatted: }
