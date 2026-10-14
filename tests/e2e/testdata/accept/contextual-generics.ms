import List from "@std/collections.ms"
import panic from "@std/faults.ms"

fn fail[T](message: String) -> Result[T, String]: error(message)

fn fail_cause[T, E](cause: E) -> Result[T, E]: error(cause)

fn absent[T]() -> Optional[T]: none

fn identity[T](value: T) -> T: value

fn from_callback[T](factory: fn() -> T) -> T: factory()

fn transform[T, U](callback: fn(value: T) -> U) -> fn(value: T) -> U: callback

type Failure:
    detail: String

impl Error for Failure:
    fn message() -> String: self.detail

fn first() -> Result[List[Int], String]: fail("empty")

fn failed() -> Result[Int, Error]: fail_cause(Failure("domain"))

fn forward[T]() -> Optional[T]: absent()

fn consume(value: Optional[Int]) -> Int: value.unwrap_or(0)

type Events:
    values: List[Int]

fn record[T](events: Events, value: Int) -> Optional[T]:
    events.values = events.values.append(value)
    return none

fn combine[T](events: Events, first: Optional[T], second: Optional[T]) -> Optional[T]:
    events.values = events.values.append(3)
    return first

test "expected generic results preserve behavior and call order":
    let result: Result[List[Int], String] = first()

    match result:
        ok(_): return panic("expected failure")
        error(message):
            if message != "empty": return panic("wrong failure")

    match failed():
        ok(_): return panic("expected domain failure")
        error(cause):
            if cause.message() != "domain": return panic("lost error dispatch")

    let empty: Optional[Int] = forward()
    if not empty.is_none(): return panic("expected none")

    let values: List[Optional[Int]] = [1, 2].map(
        fn(item): absent()
    )
    if values.length() != 2: return panic("native contextual result")
    if not values.at(0).unwrap().is_none(): return panic("native callback result")

    let callback: fn(value: Int) -> String = transform(
        fn(item): item.toString()
    )
    if callback(7) != "7": return panic("contextual callback parameter")

    let defaulted: fn(value: Int) -> Int = from_callback(
        fn(): fn(value: Int = 4): (value + 1)
    )
    if defaulted(8) != 9: return panic("contextual function result")
    if consume(identity(5)) != 5: return panic("optional argument wrapping")

    let events = Events([])
    let combined: Optional[Int] = combine(
        events: events,
        second: record(events: events, value: 2),
        first: record(events: events, value: 1)
    )
    if not combined.is_none(): return panic("nested contextual result")
    if events.values != [2, 1, 3]: return panic(
        "nested calls evaluated more than once or out of order"
    )
