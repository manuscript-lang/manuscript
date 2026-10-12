import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, String]) -> Int:
    match outcome:
        ok(value):
            return value

        error(_):
            return -1

test "data constructor context":
    let input = Input(names: [none, some(value: "Ada")])
    let success: Result[Int, String] = ok(value: 3)
    let failure: Result[Int, String] = error(cause: "unavailable")
    let absent: Optional[Int] = none
    let nested: List[List[Int]] = [
        [],
        [1]
    ]
    if not (outcome_value(outcome: success) == 3):
        return panic(message: "check failed")
    if not (outcome_value(outcome: failure) == -1):
        return panic(message: "check failed")

type Box[T]:
    value: T

type Request:
    box: Box[Optional[Int]]

fn select[T](first: T, second: T) -> T:
    return first

test "nested constructor arguments receive inferred context":
    let request = Request(box: Box(value: none))
    let provided = some(value: 3)
    let selected = select(
        first: Box(value: none),
        second: Box(value: provided)
    )

    match selected.value:
        none:
            let completed = unit

        some(_):
            return panic(message: "Unexpected case")

    match request.box.value:
        none:
            let completed = unit

        some(_):
            return panic(message: "Unexpected case")
