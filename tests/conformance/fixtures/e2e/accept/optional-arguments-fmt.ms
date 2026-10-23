# conform: tags=alternatives,closures,control-flow,faults,formatter,generics,interfaces,lists,match,modules,optional,parser,records,stdlib-errors,stdlib-queues,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/optional-arguments.ms
import {TextError} from "@std/core.ms"
import {expect_equal, expect_false} from "@std/testing.ms"
import Queue from "@std/queue.ms"

fn number(value: Optional[Int] = none) Int: value.get(-1)

fn present[T](value: Optional[T]) Optional[T]: value

fn nested(value: Optional[Optional[Int]]) Bool: value.get().is_none()

fn list_size(value: Optional[List[Int]]) Int: value.get().length()

fn flag(value: Optional[Bool]) Bool: value.get()

fn success(value: Optional[Result[Int, TextError]]) Int:
    return value.get().get(-1)

fn context[T](value: Optional[T], fallback: T) T:
    if let inner = value:
        return inner

    return fallback

type Failure:
    detail: String

impl Error for Failure:
    fn message() String: self.detail

type Notice:
    failure: Optional[Error]

type Box[T]:
    value: Optional[T]

type DefaultBox:
    value: Optional[Int] = none

type Choice[T]:
    case chosen(value: Optional[T])

interface Read:
    fn read(value: Optional[Int]) Int

type Reader:
    offset: Int

impl Read for Reader:
    fn read(value: Optional[Int]) Int: value.get(0) + self.offset

type Counter:
    calls: Int

fn next(var counter: Counter) Int:
    counter.calls += 1
    return counter.calls

fn ordered(first: Optional[Int], second: Optional[Int]) Int:
    return first.get() * 10 + second.get()

fn invoke(value: Optional[fn(value: Int) Int]) Int: value.get()(4)

fn increment(value: Int) Int: value + 1

fn calls_of(value: Optional[Counter]) Int: value.get().calls

test "plain values and explicit optionals share the call contract":
    try expect_equal(number(4), 4)
    try expect_equal(number(value: 0), 0)

    let supplied: Optional[Int] = some(4)
    try expect_equal(number(supplied), 4)
    try expect_equal(number(), -1)
    try expect_equal(number(), -1)

    let stored: fn(value: Optional[Int]) Int = number
    try expect_equal(stored(5), 5)
    try expect_equal(present(6).get(), 6)
    try expect_equal(present[Int](7).get(), 7)

    let generic_supplied: Optional[Int] = some(8)
    try expect_equal(present(generic_supplied).get(), 8)

    let missing: Optional[Int] = none
    try expect_false(not (nested(missing)))

    let outer: Optional[Optional[Int]] = some(missing)
    try expect_false(not (nested(outer)))
    try expect_equal(list_size([]), 0)
    try expect_equal(list_size([1, 2]), 2)
    try expect_equal(context(value: none, fallback: 9), 9)
    try expect_equal(context(value: [], fallback: [1]).length(), 0)
    try expect_equal(success(ok(10)), 10)
    try expect_false(flag(false))
    try expect_false(flag(true and false))
    try expect_equal(invoke(increment), 5)
    try expect_equal(invoke(fn(value): value + 2), 6)

test "constructor fields and methods use optional arguments":
    let defaulted = DefaultBox()
    try expect_false(not (defaulted.value.is_none()))

    let supplied = DefaultBox(3)
    try expect_equal(supplied.value.get(), 3)

    let box = Box(4)
    try expect_equal(box.value.get(), 4)

    let choice = Choice.chosen(5)

    match choice:
        chosen(value):
            try expect_equal(value.get(), 5)

    let reader = Reader(2)
    try expect_equal(reader.read(3), 5)

    let read = reader.read
    try expect_equal(read(4), 6)

    let view = Read(reader)
    try expect_equal(view.read(5), 7)

    let counter = Counter(9)
    try expect_equal(calls_of(counter.clone()), 9)
    try expect_equal(counter.calls, 9)

    let notice = Notice(Failure("detail"))
    try expect_equal(notice.failure.get().message(), "detail")

test "wrapping evaluates arguments once in written order":
    var counter = Counter(0)
    try expect_equal(ordered(second: next(var counter), first: next(var counter)), 21)
    try expect_equal(counter.calls, 2)

test "queue capacity accepts a plain value or omission":
    var bounded = Queue[Int](4)
    for value in [1, 2, 3, 4]:
        try expect_false(not (bounded.enqueue(value)))
    try expect_false(bounded.enqueue(5))
    try expect_equal(bounded.dequeue().get(), 1)

    var unbounded = Queue[Int]()
    var absent = Queue[Int]()
    let capacity: Optional[Int] = some(4)
    var explicit = Queue[Int](capacity)

    for value in [1, 2, 3, 4, 5]:
        try expect_false(not (unbounded.enqueue(value)))
        try expect_false(not (absent.enqueue(value)))

    try expect_false(not (explicit.enqueue(1)))
