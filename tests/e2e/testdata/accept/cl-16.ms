import {TextError} from "@std/core.ms"
import {expect_equal, expect_false} from "@std/testing.ms"

type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, TextError]) Int:
    return outcome.get(-1)

test "data constructor context":
    let _input = Input([none, some("Ada")])
    let success: Result[Int, TextError] = ok(3)
    let failure: Result[Int, TextError] = error(TextError("unavailable"))
    let _absent: Optional[Int] = none
    let _nested: List[List[Int]] = [[], [1]]

    try expect_equal(outcome_value(success), 3)
    try expect_equal(outcome_value(failure), -1)

type Box[T]:
    value: T

type Request:
    box: Box[Optional[Int]]

fn select[T](first: T, second: T) T:
    return first

test "nested constructor arguments receive inferred context":
    let request = Request(Box(none))
    let provided = some(3)
    let selected = select(Box(none), Box(provided))

    try expect_false(not selected.value.is_none())
    try expect_false(not request.box.value.is_none())
