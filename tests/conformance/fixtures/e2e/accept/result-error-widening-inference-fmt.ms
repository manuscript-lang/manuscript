# conform: tags=control-flow,formatter,generics,interfaces,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/result-error-widening-inference.ms
import expect_equal from "@std/test/test.ms"

type Failure:
    code: Int

impl Error for Failure:
    fn message() String:
        return "failure " + self.code.to_string()

fn failing() Int!Failure:
    return error(Failure(7))

fn succeeding() Int!Failure:
    return ok(3)

fn describe[T](r: T!) String:
    if r.is_error():
        return r.err().message()

    return "ok"

test "a generic T! parameter infers T and widens a domain error":
    try expect_equal(describe(failing()), "failure 7")
    try expect_equal(describe(succeeding()), "ok")
