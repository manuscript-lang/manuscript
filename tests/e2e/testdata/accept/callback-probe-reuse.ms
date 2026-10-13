import List from "@std/collections.ms"
import panic from "@std/faults.ms"

fn apply[T, U](value: T, transform: fn(value: T) -> U) -> U: transform(value)

fn choose[T](first: fn() -> T, second: fn() -> T) -> T: first()

fn optional[T, U](value: T, transform: Optional[fn(value: T) -> U]) -> U:
    return transform.unwrap()(value)

fn with_result[T](transform: fn() -> Result[T, String]) -> Result[T, String]: transform()

type Callback[T, U]:
    transform: fn(value: T) -> U

type Events:
    values: List[Int]

type Failure[T]:
    detail: T

impl Error for Failure[T]:
    fn message() -> String: self.detail.toString()

fn record(events: Events, value: Int) -> Int:
    events.values = events.values.append(value)
    return value

test "callback inference retains captures and contextual metadata":
    let events = Events([])
    let offset = 7
    let values = [1, 2].map(
        fn(outer): [3, 4].map(
            fn(inner):
                return record(
                    events: events,
                    value: outer + inner + offset
                )
        )
    )
    if values != [[11, 12], [12, 13]]: return panic("nested callback values")
    if events.values != [11, 12, 12, 13]: return panic("callback evaluation order")

    let callable: fn(value: Int) -> fn(input: Int) -> Int = apply(
        value: 1,
        transform: fn(base): fn(item): fn(extra): item + extra + base
    )
    if callable(value: 3)(input: 4) != 8: return panic("nested context labels")

    let callback = Callback(
        fn(item: Int = 4): item + offset
    )
    if callback.transform(3) != 10: return panic("constructor callback capture")
    if optional(
        value: 5,
        transform: fn(item): item + offset
    ) != 12:
        return panic("optional callback wrapping")

    let missing = choose(
        first: fn(): none,
        second: fn(): some(3)
    )
    if not missing.is_none(): return panic("failed probe needed final context")

    let failure = with_result(
        fn():
            if true: return error("expected")

            return ok(4)
    )
    if failure != Result[Int, String].error("expected"):
        return panic("partial result recheck")

    let failed: Result[Int, Error] = apply(
        value: 9,
        transform: fn(item): error(Failure(item))
    )

    match failed:
        ok(_): return panic("expected domain failure")
        error(cause):
            if cause.message() != "9": return panic("generic Error dispatch")

fn absent[T]() -> Optional[T]: none

fn from_callback[T](factory: fn() -> T) -> T: factory()

test "later returns repair incomplete and convertible evidence":
    let value = from_callback(
        fn():
            if true: return absent()

            return some(1)
    )
    if not value.is_none(): return panic("contextual absent specialization")

    let cause = from_callback(
        fn():
            if false: return Error(Failure(1))

            return Failure(2)
    )
    if cause.message() != "2": return panic("later concrete Error conversion")

fn operation() -> Result[Int, String]: ok(4)

test "try rechecks the inferred enclosing result":
    let value = from_callback(
        fn():
            let number = try operation()
            return Result[Int, String].ok(number)
    )
    if value != Result[Int, String].ok(4): return panic("try result context")
