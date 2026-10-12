import {List, Map, Set} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import Scheduler from "@std/tasks.ms"
import panic from "@std/faults.ms"

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

fn check(value: String, expected: String) -> Unit:
    if value != expected:
        panic(message: "expected {expected}, received {value}")

fn answer() -> Int:
    return 42

fn next(state: Synchronized[Int]) -> Person:
    with locked = state.lock():
        let value = locked.get()
        locked.set(value: value + 1)
        return Person(name: "Ada", age: value)

test "every scalar has toString":
    check(
        value: "hello".toString(),
        expected: "hello"
    )
    check(
        value: true.toString(),
        expected: "true"
    )
    check(
        value: false.toString(),
        expected: "false"
    )
    check(
        value: unit.toString(),
        expected: "unit"
    )
    check(
        value: (42).toString(),
        expected: "42"
    )
    check(
        value: (-7).toString(),
        expected: "-7"
    )
    check(
        value: (1.5).toString(),
        expected: "1.5"
    )
    check(
        value: (-0.0).toString(),
        expected: "-0"
    )
    check(
        value: (1.0 / 0.0).toString(),
        expected: "Infinity"
    )
    check(
        value: (0.0 / 0.0).toString(),
        expected: "NaN"
    )
    check(
        value: (1.00d).toString(),
        expected: "1"
    )

test "records alternatives and collections convert":
    let person = Person(name: "Ada", age: 37)
    check(
        value: person.toString(),
        expected: "Person(age: 37, name: Ada)"
    )
    check(
        value: "{person}",
        expected: person.toString()
    )
    check(
        value: Outcome.Ready(value: person).toString(),
        expected: "Outcome.Ready(Person(age: 37, name: Ada))"
    )
    check(
        value: Outcome.Waiting.toString(),
        expected: "Outcome.Waiting"
    )
    let absent: Optional[Int] = none
    let present: Optional[Int] = some(value: 3)
    let result: Result[Int, String] = error(cause: "failed")
    check(
        value: absent.toString(),
        expected: "Optional.none"
    )
    check(
        value: present.toString(),
        expected: "Optional.some(3)"
    )
    check(
        value: result.toString(),
        expected: "Result.error(failed)"
    )
    check(
        value: [1, 2, 3].toString(),
        expected: "[1, 2, 3]"
    )
    check(
        value: [
            [1],
            [2, 3]
        ].toString(),
        expected: "[[1], [2, 3]]"
    )
    let empty: List[Int] = []
    check(
        value: empty.toString(),
        expected: "[]"
    )
    let map = (
        Map[String, Int]()
        .with_entry(key: "b", value: 2)
        .with_entry(key: "a", value: 1)
    )
    check(
        value: map.toString(),
        expected: "Map(b: 2, a: 1)"
    )
    let set = Set[Int]().with_value(2).with_value(1)
    check(
        value: set.toString(),
        expected: "Set(2, 1)"
    )
    let bytes = Bytes(values: [0, 65, 255])
    check(
        value: bytes.toString(),
        expected: "Bytes(0, 65, 255)"
    )
    check(
        value: "{map}|{set}|{bytes}",
        expected: "Map(b: 2, a: 1)|Set(2, 1)|Bytes(0, 65, 255)"
    )

test "generics views bound methods functions and resources":
    let person = Person(name: "Ada", age: 37)
    check(
        value: stringify(person),
        expected: person.toString()
    )
    check(
        value: interpolate(person),
        expected: person.toString()
    )
    check(
        value: bound_stringify(person),
        expected: person.toString()
    )
    let view = Named(value: person)
    check(
        value: view.toString(),
        expected: person.toString()
    )
    check(
        value: "{view}",
        expected: person.toString()
    )
    let convert: fn() -> String = view.toString
    check(
        value: convert(),
        expected: person.toString()
    )
    check(
        value: answer.toString(),
        expected: "[function]"
    )
    check(value: "{answer}", expected: "[function]")
    let queue = Queue[Int](capacity: some(value: 1))
    check(
        value: queue.toString(),
        expected: "[object]"
    )
    check(value: "{queue}", expected: "[object]")

    with service = Scheduler(limit: some(value: 1)):
        check(
            value: service.toString(),
            expected: "[object]"
        )
        check(value: "{service}", expected: "[object]")
        let bound = service.toString
        service.close()
        check(
            value: bound(),
            expected: "[object]"
        )

test "interpolation and bound conversion evaluate each receiver once":
    let state = Synchronized[Int](value: 1)
    check(
        value: "{next(state)}|{next(state)}",
        expected: "Person(age: 1, name: Ada)|Person(age: 2, name: Ada)"
    )
    let convert = next(state).toString
    check(
        value: convert(),
        expected: "Person(age: 3, name: Ada)"
    )
    check(
        value: convert(),
        expected: "Person(age: 3, name: Ada)"
    )

    with locked = state.lock():
        check(
            value: locked.get().toString(),
            expected: "4"
        )
