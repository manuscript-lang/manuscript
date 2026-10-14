import List from "@std/collections.ms"
import panic from "@std/faults.ms"

fn identity[T](value: T) -> T: value

fn first[T](left: T, right: T) -> T: left

fn optional[T](value: Optional[T], fallback: T) -> T: value.unwrap_or(fallback)

fn describe[T](value: T, cause: Error) -> String: cause.message()

type Events:
    values: List[Int]

type Failure:
    detail: String

impl Error for Failure:
    fn message() -> String: self.detail

type GenericFailure[T]:
    detail: T

impl Error for GenericFailure[T]:
    fn message() -> String: self.detail.toString()

fn record(events: Events, value: Int) -> Int:
    events.values = events.values.append(value)
    return value

test "reused inference preserves evaluation and argument conversions":
    let events = Events([])
    let selected = first(
        right: identity(identity(record(events: events, value: 2))),
        left: identity(identity(record(events: events, value: 1)))
    )
    if selected != 1: return panic("wrong inferred argument")
    if events.values != [2, 1]: return panic("argument order or repeated evaluation")

    let wrapped = optional(
        value: identity(record(events: events, value: 3)),
        fallback: 0
    )
    if wrapped != 3: return panic("lost optional wrapping")
    if events.values != [2, 1, 3]: return panic("optional argument evaluated twice")

    let message = describe(value: 1, cause: identity(Failure("cached")))
    if message != "cached": return panic("lost Error conversion")

    let generic_message = describe(value: 1, cause: identity(GenericFailure(4)))
    if generic_message != "4": return panic("lost generic Error dispatch")

    let offset = 7
    let callback = identity(identity(fn(value: Int): offset + value))
    if callback(3) != 10: return panic("lost callback capture")
