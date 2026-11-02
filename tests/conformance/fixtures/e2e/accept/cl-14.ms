# conform: tags=alternatives,control-flow,faults,interfaces,modules,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-14.ms
import expect_equal from "@std/test/test.ms"

type Problem:
    case Missing(reason: String)

type OtherProblem:
    case Invalid(reason: String)

fn checked(value: Int) Int!Problem:
    if value < 0:
        return error(Problem.Missing("negative"))

    return ok(value)

fn doubled(value: Int) Int!Problem:
    let accepted = try checked(value)
    return ok(accepted * 2)

fn summarize(outcome: Int!Problem) Int:
    return outcome.get(-1)

test "unchanged propagated error":
    try expect_equal(summarize(doubled(3)), 6)
    try expect_equal(summarize(doubled(-1)), -1)
