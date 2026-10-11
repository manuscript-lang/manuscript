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
    let nested: List[List[Int]] = [[], [1]]
    assert outcome_value(outcome: success) == 3
    assert outcome_value(outcome: failure) == -1

type Box[T]:
    value: T

type Request:
    box: Box[Optional[Int]]

fn select[T](first: T, second: T) -> T:
    return first

test "nested constructor arguments receive inferred context":
    let request = Request(box: Box(value: none))
    let selected = select(first: Box(value: none), second: Box(value: some(value: 3)))
    match selected.value:
        none:
            assert true
        some(_):
            assert false
    match request.box.value:
        none:
            assert true
        some(_):
            assert false
