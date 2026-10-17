import Queue from "@std/queues.ms"
import panic from "@std/faults.ms"

fn number(value: Optional[Int] = none) -> Int: value.unwrap_or(-1)

fn present[T](value: Optional[T]) -> Optional[T]: value

fn nested(value: Optional[Optional[Int]]) -> Bool: value.unwrap().is_none()

fn list_size(value: Optional[List[Int]]) -> Int: value.unwrap().length()

fn flag(value: Optional[Bool]) -> Bool: value.unwrap()

fn success(value: Optional[Result[Int, String]]) -> Int:
    return value.unwrap().unwrap_or(-1)

fn context[T](value: Optional[T], fallback: T) -> T: value.unwrap_or(fallback)

type Failure:
    detail: String

impl Error for Failure:
    fn message() -> String: self.detail

type Notice:
    failure: Optional[Error]

type Box[T]:
    value: Optional[T]

type DefaultBox:
    value: Optional[Int] = none

type Choice[T]:
    case chosen(value: Optional[T])

interface Read:
    fn read(value: Optional[Int]) -> Int

type Reader:
    offset: Int

impl Read for Reader:
    fn read(value: Optional[Int]) -> Int: value.unwrap_or(0) + self.offset

type Counter:
    calls: Int

fn next(counter: Counter) -> Int:
    counter.calls = counter.calls + 1
    return counter.calls

fn ordered(first: Optional[Int], second: Optional[Int]) -> Int:
    return first.unwrap() * 10 + second.unwrap()

fn invoke(value: Optional[fn(value: Int) -> Int]) -> Int: value.unwrap()(4)

fn increment(value: Int) -> Int: value + 1

fn mutate(value: Optional[Counter]) -> Unit: value.unwrap().calls = 9

test "plain values and explicit optionals share the call contract":
    if number(4) != 4: return panic("plain argument")
    if number(value: 0) != 0: return panic("zero must be present")

    let supplied: Optional[Int] = some(4)
    if number(supplied) != 4: return panic("explicit some")
    if number() != -1: return panic("explicit none")
    if number() != -1: return panic("default none")

    let stored: fn(value: Optional[Int]) -> Int = number
    if stored(5) != 5: return panic("stored function")
    if present(6).unwrap() != 6: return panic("generic inference")
    if present[Int](7).unwrap() != 7: return panic("explicit specialization")

    let generic_supplied: Optional[Int] = some(8)
    if present(generic_supplied).unwrap() != 8: return panic(
        "generic optional identity"
    )

    let missing: Optional[Int] = none
    if not (nested(missing)): return panic("nested none must be wrapped once")

    let outer: Optional[Optional[Int]] = some(missing)
    if not (nested(outer)): return panic("nested optional identity")
    if list_size([]) != 0: return panic("empty payload context")
    if list_size([1, 2]) != 2: return panic("list payload")
    if context(value: none, fallback: 9) != 9: return panic("generic none context")
    if context(value: [], fallback: [1]).length() != 0: return panic(
        "generic list context"
    )
    if success(ok(10)) != 10: return panic("result payload context")
    if flag(false): return panic("false must be present")
    if flag(true and false): return panic("folded false must be wrapped")
    if invoke(increment) != 5: return panic("function payload")
    if invoke(fn(value): value + 2) != 6: return panic("closure payload")

test "constructor fields and methods use optional arguments":
    let defaulted = DefaultBox()
    if not (defaulted.value.is_none()): return panic("optional record default")

    let supplied = DefaultBox(3)
    if supplied.value.unwrap() != 3: return panic(
        "optional argument with record default"
    )

    let box = Box(4)
    if box.value.unwrap() != 4: return panic("generic record constructor")

    let choice = Choice.chosen(5)

    match choice:
        chosen(value):
            if value.unwrap() != 5: return panic("generic alternative constructor")

    let reader = Reader(2)
    if reader.read(3) != 5: return panic("method argument")

    let read = reader.read
    if read(4) != 6: return panic("bound method argument")

    let view = Read(reader)
    if view.read(5) != 7: return panic("interface argument")

    let counter = Counter(0)
    mutate(counter)
    if counter.calls != 9: return panic("wrapping copied the payload")

    let notice = Notice(Failure("detail"))
    if notice.failure.unwrap().message() != "detail": return panic(
        "error payload conversion"
    )

test "wrapping evaluates arguments once in written order":
    let counter = Counter(0)
    if ordered(second: next(counter), first: next(counter)) != 21:
        return panic("argument order changed")
    if counter.calls != 2: return panic("argument evaluated more than once")

test "queue capacity accepts a plain value or omission":
    let bounded = Queue[Int](4)
    for value in [1, 2, 3, 4]:
        if not (bounded.enqueue(value)): return panic("capacity rejected a value")
    if bounded.enqueue(5): return panic("capacity bound was lost")
    if bounded.dequeue().unwrap() != 1: return panic("queue order changed")

    let unbounded = Queue[Int]()
    let absent = Queue[Int]()
    let capacity: Optional[Int] = some(4)
    let explicit = Queue[Int](capacity)

    for value in [1, 2, 3, 4, 5]:
        if not (unbounded.enqueue(value)): return panic(
            "omitted capacity became bounded"
        )
        if not (absent.enqueue(value)): return panic("none capacity became bounded")

    if not (explicit.enqueue(1)): return panic("explicit capacity changed")
