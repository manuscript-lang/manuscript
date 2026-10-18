import panic from "@std/faults.ms"

type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, String]) Int:
    return outcome.unwrap_or(-1)

test "data constructor context":
    let _input = Input([none, some("Ada")])
    let success: Result[Int, String] = ok(3)
    let failure: Result[Int, String] = error("unavailable")
    let _absent: Optional[Int] = none
    let _nested: List[List[Int]] = [[], [1]]
    if not (outcome_value(outcome: success) == 3):
        return panic(message: "check failed")
    if not (outcome_value(outcome: failure) == -1):
        return panic(message: "check failed")

type Box[T]:
    value: T

type Request:
    box: Box[Optional[Int]]

fn select[T](first: T, second: T) T:
    return first

test "nested constructor arguments receive inferred context":
    let request = Request(Box(none))
    let provided = some(3)
    let selected = select(first: Box(none), second: Box(provided))
    if not selected.value.is_none():
        return panic(message: "Unexpected case")
    if not request.box.value.is_none():
        return panic(message: "Unexpected case")
