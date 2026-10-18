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
    fn name() String

impl Named for Person:
    fn name() String:
        return self.name

fn stringify[T](value: T) String:
    return value.to_string()

fn interpolate[T](value: T) String:
    return "{value}"

fn bound_stringify[T: Named](value: T) String:
    return value.to_string()

fn check(value: String, expected: String) Unit:
    if value != expected:
        panic("expected {expected}, received {value}")

fn answer() Int:
    return 42

fn next(state: Synchronized[Int]) Person:
    with locked = state.lock():
        let value = locked.get()
        locked.set(value + 1)
        return Person("Ada", value)

test "every scalar has to_string":
    check("hello".to_string(), "hello")
    check(true.to_string(), "true")
    check(false.to_string(), "false")
    check(unit.to_string(), "unit")
    check((42).to_string(), "42")
    check((-7).to_string(), "-7")
    check((1.5).to_string(), "1.5")
    check((-0.0).to_string(), "-0")
    check((1.0 / 0.0).to_string(), "Infinity")
    check((0.0 / 0.0).to_string(), "NaN")
    check((1.00d).to_string(), "1")

test "records alternatives and collections convert":
    let person = Person("Ada", 37)
    check(person.to_string(), "Person(age: 37, name: Ada)")
    check("{person}", person.to_string())
    check(
        Outcome.Ready(person).to_string(),
        "Outcome.Ready(Person(age: 37, name: Ada))"
    )
    check(Outcome.Waiting.to_string(), "Outcome.Waiting")
    let absent: Optional[Int] = none
    let present: Optional[Int] = some(3)
    let result: Result[Int, String] = error("failed")
    check(absent.to_string(), "Optional.none")
    check(present.to_string(), "Optional.some(3)")
    check(result.to_string(), "Result.error(failed)")
    check([1, 2, 3].to_string(), "[1, 2, 3]")
    check([[1], [2, 3]].to_string(), "[[1], [2, 3]]")
    let empty: List[Int] = []
    check(empty.to_string(), "[]")
    let map = (Map[String, Int]().add("b", 2).add("a", 1))
    check(map.to_string(), "Map(b: 2, a: 1)")
    let set = Set[Int]().add(2).add(1)
    check(set.to_string(), "Set(2, 1)")
    let bytes = Bytes([0, 65, 255])
    check(bytes.to_string(), "Bytes(0, 65, 255)")
    check("{map}|{set}|{bytes}", "Map(b: 2, a: 1)|Set(2, 1)|Bytes(0, 65, 255)")

test "generics views bound methods functions and resources":
    let person = Person("Ada", 37)
    check(stringify(person), person.to_string())
    check(interpolate(person), person.to_string())
    check(bound_stringify(person), person.to_string())
    let view = Named(person)
    check(view.to_string(), person.to_string())
    check("{view}", person.to_string())
    let convert: fn() String = view.to_string
    check(convert(), person.to_string())
    check(answer.to_string(), "[function]")
    check("{answer}", "[function]")
    let queue = Queue[Int](1)
    check(queue.to_string(), "[object]")
    check("{queue}", "[object]")

    with service = Scheduler(1):
        check(service.to_string(), "[object]")
        check("{service}", "[object]")
        let bound = service.to_string
        service.close()
        check(bound(), "[object]")

test "interpolation and bound conversion evaluate each receiver once":
    let state = Synchronized[Int](1)
    check(
        "{next(state)}|{next(state)}",
        "Person(age: 1, name: Ada)|Person(age: 2, name: Ada)"
    )
    let convert = next(state).to_string
    check(convert(), "Person(age: 3, name: Ada)")
    check(convert(), "Person(age: 3, name: Ada)")
    with locked = state.lock():
        check(locked.get().to_string(), "4")
