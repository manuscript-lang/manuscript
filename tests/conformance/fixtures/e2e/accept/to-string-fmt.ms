# conform: tags=aliasing,alternatives,closures,control-flow,decimal,formatter,generics,interfaces,interpolation,lists,maps,modules,optional,parser,records,sets,stdlib-bytes,stdlib-decimal,stdlib-errors,stdlib-queues,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/to-string.ms
from "@std/core.ms" import TextError
from "@std/testing.ms" import fail
from "@std/bytes.ms" import Bytes
from "@std/decimal.ms" import Decimal
from "@std/queue.ms" import Queue

type Person:
    name: String
    age: Int

type Outcome:
    case Ready(value: Person)
    case Waiting

interface Named:
    def name() -> String

impl Named for Person:
    def name() -> String:
        return self.name

def stringify[T](value: T) -> String:
    return value.to_string()

def interpolate[T](value: T) -> String:
    return f"{value}"

def bound_stringify[T: Named](value: T) -> String:
    return value.to_string()

def check(value: String, expected: String) -> Result[Unit, Error]:
    if value != expected: return fail(message: f"expected {expected}, received {value}")

    return ok(())

def answer() -> Int:
    return 42

type Counter:
    value: Int

def next(var state: Counter) -> Person:
    let value = state.value
    state.value = value + 1
    return Person(name: "Ada", age: value)

test "every scalar has to_string":
    (try check(value: "hello".to_string(), expected: "hello"))
    (try check(value: True.to_string(), expected: "true"))
    (try check(value: False.to_string(), expected: "false"))
    (try check(value: ().to_string(), expected: "unit"))
    (try check(value: (42).to_string(), expected: "42"))
    (try check(value: (-7).to_string(), expected: "-7"))
    (try check(value: (1.5).to_string(), expected: "1.5"))
    (try check(value: (-0.0).to_string(), expected: "-0"))
    (try check(value: (1.0 / 0.0).to_string(), expected: "Infinity"))
    (try check(value: (0.0 / 0.0).to_string(), expected: "NaN"))
    (try check(value: (1.00d).to_string(), expected: "1"))

test "records alternatives and collections convert":
    let person = Person(name: "Ada", age: 37)
    (try check(value: person.to_string(), expected: "Person(age: 37, name: Ada)"))
    (try check(value: f"{person}", expected: person.to_string()))
    (
        try check(
            value: Outcome.Ready(person).to_string(),
            expected: "Outcome.Ready(Person(age: 37, name: Ada))"
        )
    )
    (try check(value: Outcome.Waiting.to_string(), expected: "Outcome.Waiting"))

    let absent: Optional[Int] = none
    let present: Optional[Int] = some(3)
    let result: Result[Int, TextError] = error(TextError("failed"))
    (try check(value: absent.to_string(), expected: "Optional.none"))
    (try check(value: present.to_string(), expected: "Optional.some(3)"))
    (
        try check(
            value: result.to_string(), expected: "Result.error(TextError(text: failed))"
        )
    )
    (try check(value: [1, 2, 3].to_string(), expected: "[1, 2, 3]"))
    (try check(value: [[1], [2, 3]].to_string(), expected: "[[1], [2, 3]]"))

    let empty: List[Int] = []
    (try check(value: empty.to_string(), expected: "[]"))

    var map = Map[String, Int]()
    map.add(key: "b", value: 2)
    map.add(key: "a", value: 1)
    (try check(value: map.to_string(), expected: "Map(b: 2, a: 1)"))

    let set = Set[Int]([2, 1])
    (try check(value: set.to_string(), expected: "Set(2, 1)"))

    let bytes = Bytes([0, 65, 255])
    (try check(value: bytes.to_string(), expected: "Bytes(0, 65, 255)"))
    (
        try check(
            value: f"{map}|{set}|{bytes}",
            expected: "Map(b: 2, a: 1)|Set(2, 1)|Bytes(0, 65, 255)"
        )
    )

test "generics views bound methods functions and resources":
    let person = Person(name: "Ada", age: 37)
    (try check(value: stringify(person), expected: person.to_string()))
    (try check(value: interpolate(person), expected: person.to_string()))
    (try check(value: bound_stringify(person), expected: person.to_string()))

    let view = Named(person)
    (try check(value: view.to_string(), expected: person.to_string()))
    (try check(value: f"{view}", expected: person.to_string()))

    let convert: Callable[[], String] = view.to_string
    (try check(value: convert(), expected: person.to_string()))
    (try check(value: answer.to_string(), expected: "[function]"))
    (try check(value: f"{answer}", expected: "[function]"))

    var queue = Queue[Int](1)
    (try check(value: queue.to_string(), expected: "[object]"))
    (try check(value: f"{queue}", expected: "[object]"))

test "interpolation and bound conversion evaluate each receiver once":
    var state = Counter(value: 1)
    (
        try check(
            value: f"{next(var state)}|{next(var state)}",
            expected: "Person(age: 1, name: Ada)|Person(age: 2, name: Ada)"
        )
    )

    let convert = next(var state).to_string
    (try check(value: convert(), expected: "Person(age: 3, name: Ada)"))
    (try check(value: convert(), expected: "Person(age: 3, name: Ada)"))
    (try check(value: state.value.to_string(), expected: "4"))
