import panic from "@std/faults.ms"

import Result from "@std/result.ms"

type Problem:
    case Missing(reason: String)

type OtherProblem:
    case Invalid(reason: String)

fn checked(value: Int) -> Result[Int, Problem]:
    if value < 0:
        return error(cause: Problem.Missing(reason: "negative"))

    return ok(value: value)

fn doubled(value: Int) -> Result[Int, Problem]:
    let accepted = try checked(value: value)
    return ok(value: accepted * 2)

fn summarize(outcome: Result[Int, Problem]) -> Int:
    match outcome:
        ok(value):
            return value

        error(_):
            return -1

test "unchanged propagated error":
    if not (summarize(outcome: doubled(value: 3)) == 6):
        return panic(message: "check failed")
    if not (summarize(outcome: doubled(value: -1)) == -1):
        return panic(message: "check failed")
