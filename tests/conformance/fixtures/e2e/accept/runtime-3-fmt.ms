# conform: tags=closures,control-flow,formatter,generics,interfaces,interpolation,match,modules,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/runtime-3.ms
import expect_equal, expect_true, fail from "@std/test/test.ms"

fn identity[T](value: T) T:
    return value

fn probe() Unit!:
    let first = fn() Int!Error:
        return ok(3)
    let second = fn:
        return true
    let number = identity(first)()
    let flag = second()
    (flag) | try expect_true

    match number:
        ok(value):
            try expect_equal(value, 3)
        error(_):
            return fail(message: "Unexpected case")

    return ok(unit)

test "typed callback helper":
    match probe():
        ok(_):
            let _completed = unit
        error(_):
            return fail(message: "Unexpected case")

type Code:
    number: Int

fn describe(outcome: Int!Code) Int!Error:
    match outcome:
        ok(value):
            return ok(value)
        error(cause):
            return error(Error("Error {cause.number}"))

test "explicit error conversion":
    let failed: Int!Code = error(Code(7))
    let expected: Int!Error = error(Error("Error 7"))
    describe(outcome: failed) | try expect_equal(expected)

    let succeeded: Int!Code = ok(3)
    let unchanged: Int!Error = ok(3)
    describe(outcome: succeeded) | try expect_equal(unchanged)
