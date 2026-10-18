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
    return value.toString()

fn interpolate[T](value: T) String:
    return "{value}"

fn bound_stringify[T: Named](value: T) String:
    return value.toString()

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

test "every scalar has toString":
    check("hello".toString(), "hello")
    check(true.toString(), "true")
    check(false.toString(), "false")
    check(unit.toString(), "unit")
    check((42).toString(), "42")
    check((-7).toString(), "-7")
    check((1.5).toString(), "1.5")
    check((-0.0).toString(), "-0")
    check((1.0 / 0.0).toString(), "Infinity")
    check((0.0 / 0.0).toString(), "NaN")
    check((1.00d).toString(), "1")

test "records alternatives and collections convert":
    let person = Person("Ada", 37)
    check(person.toString(), "Person(age: 37, name: Ada)")
    check("{person}", person.toString())
    check(Outcome.Ready(person).toString(), "Outcome.Ready(Person(age: 37, name: Ada))")
    check(Outcome.Waiting.toString(), "Outcome.Waiting")
    let absent: Optional[Int] = none
    let present: Optional[Int] = some(3)
    let result: Result[Int, String] = error("failed")
    check(absent.toString(), "Optional.none")
    check(present.toString(), "Optional.some(3)")
    check(result.toString(), "Result.error(failed)")
    check([1, 2, 3].toString(), "[1, 2, 3]")
    check([[1], [2, 3]].toString(), "[[1], [2, 3]]")
    let empty: List[Int] = []
    check(empty.toString(), "[]")
    let map = (Map[String, Int]().add("b", 2).add("a", 1))
    check(map.toString(), "Map(b: 2, a: 1)")
    let set = Set[Int]().add(2).add(1)
    check(set.toString(), "Set(2, 1)")
    let bytes = Bytes([0, 65, 255])
    check(bytes.toString(), "Bytes(0, 65, 255)")
    check("{map}|{set}|{bytes}", "Map(b: 2, a: 1)|Set(2, 1)|Bytes(0, 65, 255)")

test "generics views bound methods functions and resources":
    let person = Person("Ada", 37)
    check(stringify(person), person.toString())
    check(interpolate(person), person.toString())
    check(bound_stringify(person), person.toString())
    let view = Named(person)
    check(view.toString(), person.toString())
    check("{view}", person.toString())
    let convert: fn() String = view.toString
    check(convert(), person.toString())
    check(answer.toString(), "[function]")
    check("{answer}", "[function]")
    let queue = Queue[Int](1)
    check(queue.toString(), "[object]")
    check("{queue}", "[object]")

    with service = Scheduler(1):
        check(service.toString(), "[object]")
        check("{service}", "[object]")
        let bound = service.toString
        service.close()
        check(bound(), "[object]")

test "interpolation and bound conversion evaluate each receiver once":
    let state = Synchronized[Int](1)
    check(
        "{next(state)}|{next(state)}",
        "Person(age: 1, name: Ada)|Person(age: 2, name: Ada)"
    )
    let convert = next(state).toString
    check(convert(), "Person(age: 3, name: Ada)")
    check(convert(), "Person(age: 3, name: Ada)")
    with locked = state.lock():
        check(locked.get().toString(), "4")
