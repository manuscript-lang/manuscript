import {expect_equal, fail} from "@std/testing.ms"

type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, String]) -> Int:
    match outcome:
        ok(value):
            return value
        error(_):
            return -1

test "data constructor context":
    let input = Input([none, some("Ada")])
    let success: Result[Int, String] = ok(3)
    let failure: Result[Int, String] = error("unavailable")
    let absent: Optional[Int] = none
    let nested: List[List[Int]] = [[], [1]]
    outcome_value(outcome: success) | try expect_equal(expected: 3)
    outcome_value(outcome: failure) | try expect_equal(expected: -1)

type Box[T]:
    value: T

type Request:
    box: Box[Optional[Int]]

fn select[T](first: T, second: T) -> T:
    return first

test "nested constructor arguments receive inferred context":
    let request = Request(Box(none))
    let provided = some(3)
    let selected = select(first: Box(none), second: Box(provided))

    match selected.value:
        none:
            let completed = unit
        some(_):
            return fail(message: "Unexpected case")

    match request.box.value:
        none:
            let completed = unit
        some(_):
            return fail(message: "Unexpected case")
