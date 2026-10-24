# conform: tags=control-flow,generics,interfaces,modules,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/result-error-widening-inference.ms
from "@std/testing.ms" import expect_equal

type Failure:
    code: Int

impl Error for Failure:
    def message() -> String:
        return "failure " + self.code.to_string()

def failing() -> Result[Int, Failure]:
    return error(Failure(7))

def succeeding() -> Result[Int, Failure]:
    return ok(3)

def describe[T](r: Result[T, Error]) -> String:
    if r.is_error():
        return r.err().message()

    return "ok"

test "a generic Result[T, Error] parameter infers T and widens a domain error":
    try expect_equal(describe(failing()), "failure 7")
    try expect_equal(describe(succeeding()), "ok")
