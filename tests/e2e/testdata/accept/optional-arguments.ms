import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import Queue from "@std/queues.ms"

fn number(value: Optional[Int] = none) -> Int: value.unwrap_or(-1)

fn present[T](value: Optional[T]) -> Optional[T]: value

fn nested(value: Optional[Optional[Int]]) -> Bool: value.unwrap().is_none()

fn list_size(value: Optional[List[Int]]) -> Int: value.unwrap().length()

fn flag(value: Optional[Bool]) -> Bool: value.unwrap()

fn success(value: Optional[Result[Int, String]]) -> Int:
    match value.unwrap():
        ok(value): return value
        error(_): return -1

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
    number(4) | try expect_equal(expected: 4)
    number(value: 0) | try expect_equal(expected: 0)
    let supplied: Optional[Int] = some(4)
    number(supplied) | try expect_equal(expected: 4)
    number() | try expect_equal(expected: -1)
    number() | try expect_equal(expected: -1)
    let stored: fn(value: Optional[Int]) -> Int = number
    stored(5) | try expect_equal(expected: 5)
    present(6).unwrap() | try expect_equal(expected: 6)
    present[Int](7).unwrap() | try expect_equal(expected: 7)
    let generic_supplied: Optional[Int] = some(8)
    present(generic_supplied).unwrap() | try expect_equal(expected: 8)
    let missing: Optional[Int] = none
    (nested(missing)) | try expect_true
    let outer: Optional[Optional[Int]] = some(missing)
    (nested(outer)) | try expect_true
    list_size([]) | try expect_equal(expected: 0)
    list_size([1, 2]) | try expect_equal(expected: 2)
    context(value: none, fallback: 9) | try expect_equal(expected: 9)
    context(value: [], fallback: [1]).length() | try expect_equal(expected: 0)
    success(ok(10)) | try expect_equal(expected: 10)
    flag(false) | try expect_false
    flag(true and false) | try expect_false
    invoke(increment) | try expect_equal(expected: 5)
    try expect_equal(invoke(fn(value): value + 2), 6)

test "constructor fields and methods use optional arguments":
    let defaulted = DefaultBox()
    (defaulted.value.is_none()) | try expect_true
    let supplied = DefaultBox(3)
    supplied.value.unwrap() | try expect_equal(expected: 3)
    let box = Box(4)
    box.value.unwrap() | try expect_equal(expected: 4)
    let choice = Choice.chosen(5)

    match choice:
        chosen(value):
            try expect_equal(value.unwrap(), 5)

    let reader = Reader(2)
    reader.read(3) | try expect_equal(expected: 5)
    let read = reader.read
    read(4) | try expect_equal(expected: 6)
    let view = Read(reader)
    view.read(5) | try expect_equal(expected: 7)
    let counter = Counter(0)
    mutate(counter)
    counter.calls | try expect_equal(expected: 9)
    let notice = Notice(Failure("detail"))
    notice.failure.unwrap().message() | try expect_equal(expected: "detail")

test "wrapping evaluates arguments once in written order":
    let counter = Counter(0)
    ordered(second: next(counter), first: next(counter)) | try expect_equal(
        expected: 21
    )
    counter.calls | try expect_equal(expected: 2)

test "queue capacity accepts a plain value or omission":
    let bounded = Queue[Int](4)
    for value in [1, 2, 3, 4]:
        (bounded.enqueue(value)) | try expect_true
    bounded.enqueue(5) | try expect_false
    bounded.dequeue().unwrap() | try expect_equal(expected: 1)
    let unbounded = Queue[Int]()
    let absent = Queue[Int]()
    let capacity: Optional[Int] = some(4)
    let explicit = Queue[Int](capacity)

    for value in [1, 2, 3, 4, 5]:
        (unbounded.enqueue(value)) | try expect_true
        (absent.enqueue(value)) | try expect_true

    (explicit.enqueue(1)) | try expect_true
