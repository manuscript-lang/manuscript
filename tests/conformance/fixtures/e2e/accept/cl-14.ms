# conform: tags=alternatives,control-flow,faults,interfaces,modules,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-14.ms
from "@std/test.ms" import expect_equal

type Problem:
    case Missing(reason: String)

impl Error for Problem:
    def message() -> String: "Problem"

type OtherProblem:
    case Invalid(reason: String)

def checked(value: Int) -> Result[Int, Problem]:
    if value < 0:
        return error(Problem.Missing("negative"))

    return ok(value)

def doubled(value: Int) -> Result[Int, Problem]:
    let accepted = try checked(value)
    return ok(accepted * 2)

def summarize(outcome: Result[Int, Problem]) -> Int:
    return outcome.get(-1)

test "unchanged propagated error":
    try expect_equal(summarize(doubled(3)), 6)
    try expect_equal(summarize(doubled(-1)), -1)
