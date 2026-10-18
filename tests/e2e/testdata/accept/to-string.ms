import {fail} from "@std/testing.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import Scheduler from "@std/tasks.ms"

type Person:
    name: String
    age: Int

type Outcome:
    case Ready(value: Person)
    case Waiting

interface Named:
    fn name() -> String

impl Named for Person:
    fn name() -> String:
        return self.name

fn stringify[T](value: T) -> String:
    return value.toString()

fn interpolate[T](value: T) -> String:
    return "{value}"

fn bound_stringify[T: Named](value: T) -> String:
    return value.toString()

fn check(value: String, expected: String) -> Result[Unit, Error]:
    if value != expected: return fail(message: "expected {expected}, received {value}")

    return ok(unit)

fn answer() -> Int:
    return 42

fn next(state: Synchronized[Int]) -> Person:
    with locked = state.lock():
        let value = locked.get()
        locked.set(value: value + 1)
        return Person(name: "Ada", age: value)

test "every scalar has toString":
    (try check(value: "hello".toString(), expected: "hello"))
    (try check(value: true.toString(), expected: "true"))
    (try check(value: false.toString(), expected: "false"))
    (try check(value: unit.toString(), expected: "unit"))
    (try check(value: (42).toString(), expected: "42"))
    (try check(value: (-7).toString(), expected: "-7"))
    (try check(value: (1.5).toString(), expected: "1.5"))
    (try check(value: (-0.0).toString(), expected: "-0"))
    (try check(value: (1.0 / 0.0).toString(), expected: "Infinity"))
    (try check(value: (0.0 / 0.0).toString(), expected: "NaN"))
    (try check(value: (1.00d).toString(), expected: "1"))

test "records alternatives and collections convert":
    let person = Person(name: "Ada", age: 37)
    (try check(value: person.toString(), expected: "Person(age: 37, name: Ada)"))
    (try check(value: "{person}", expected: person.toString()))
    (
        try check(
            value: Outcome.Ready(person).toString(),
            expected: "Outcome.Ready(Person(age: 37, name: Ada))"
        )
    )
    (try check(value: Outcome.Waiting.toString(), expected: "Outcome.Waiting"))
    let absent: Optional[Int] = none
    let present: Optional[Int] = some(3)
    let result: Result[Int, String] = error("failed")
    (try check(value: absent.toString(), expected: "Optional.none"))
    (try check(value: present.toString(), expected: "Optional.some(3)"))
    (try check(value: result.toString(), expected: "Result.error(failed)"))
    (try check(value: [1, 2, 3].toString(), expected: "[1, 2, 3]"))
    (try check(value: [[1], [2, 3]].toString(), expected: "[[1], [2, 3]]"))
    let empty: List[Int] = []
    (try check(value: empty.toString(), expected: "[]"))
    let map = (Map[String, Int]().add(key: "b", value: 2).add(key: "a", value: 1))
    (try check(value: map.toString(), expected: "Map(b: 2, a: 1)"))
    let set = Set[Int]().add(2).add(1)
    (try check(value: set.toString(), expected: "Set(2, 1)"))
    let bytes = Bytes([0, 65, 255])
    (try check(value: bytes.toString(), expected: "Bytes(0, 65, 255)"))
    (
        try check(
            value: "{map}|{set}|{bytes}",
            expected: "Map(b: 2, a: 1)|Set(2, 1)|Bytes(0, 65, 255)"
        )
    )

test "generics views bound methods functions and resources":
    let person = Person(name: "Ada", age: 37)
    (try check(value: stringify(person), expected: person.toString()))
    (try check(value: interpolate(person), expected: person.toString()))
    (try check(value: bound_stringify(person), expected: person.toString()))
    let view = Named(person)
    (try check(value: view.toString(), expected: person.toString()))
    (try check(value: "{view}", expected: person.toString()))
    let convert: fn() -> String = view.toString
    (try check(value: convert(), expected: person.toString()))
    (try check(value: answer.toString(), expected: "[function]"))
    (try check(value: "{answer}", expected: "[function]"))
    let queue = Queue[Int](1)
    (try check(value: queue.toString(), expected: "[object]"))
    (try check(value: "{queue}", expected: "[object]"))

    with service = Scheduler(limit: 1):
        (try check(value: service.toString(), expected: "[object]"))
        (try check(value: "{service}", expected: "[object]"))
        let bound = service.toString
        service.close()
        (try check(value: bound(), expected: "[object]"))

test "interpolation and bound conversion evaluate each receiver once":
    let state = Synchronized[Int](1)
    (
        try check(
            value: "{next(state)}|{next(state)}",
            expected: "Person(age: 1, name: Ada)|Person(age: 2, name: Ada)"
        )
    )
    let convert = next(state).toString
    (try check(value: convert(), expected: "Person(age: 3, name: Ada)"))
    (try check(value: convert(), expected: "Person(age: 3, name: Ada)"))
    with locked = state.lock():
        (try check(value: locked.get().toString(), expected: "4"))
