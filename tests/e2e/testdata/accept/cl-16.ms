import panic from "@std/faults.ms"

type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, String]) Int:
    return outcome.get(-1)

test "data constructor context":
    let _input = Input([none, some("Ada")])
    let success: Result[Int, String] = ok(3)
    let failure: Result[Int, String] = error("unavailable")
    let _absent: Optional[Int] = none
    let _nested: List[List[Int]] = [[], [1]]
    if not (outcome_value(success) == 3):
        return panic("check failed")
    if not (outcome_value(failure) == -1):
        return panic("check failed")

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
    if not selected.value.is_none():
        return panic("Unexpected case")
    if not request.box.value.is_none():
        return panic("Unexpected case")
