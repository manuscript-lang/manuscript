// conform: tags=alternatives,closures,control-flow,faults,formatter,generics,interfaces,lists,match,modules,optional,parser,records,stdlib-errors,stdlib-queues,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/optional-arguments.ms
import expect_equal, expect_false from "@std/test/test.ms"
import Queue from "@std/collections/queue.ms"

fn number(value: Int?) Int: value.get(-1)

fn present[T](value: T?) T?: value

fn nested(value: Int??) Bool: value.get().is_none()

fn list_size(value: List[Int]?) Int: value.get().length()

fn flag(value: Bool?) Bool: value.get()

fn success(value: Int!Error?) Int:
    return value.get().get(-1)

fn context[T](value: T?, fallback: T) T:
    if inner := value:
        return inner

    return fallback

type Notice:
    failure: Error?

type Box[T]:
    value: T?

type DefaultBox:
    value: Int?

enum Choice[T]:
    chosen(value: T?)

interface Read:
    fn read(value: Int?) Int

type Reader:
    offset: Int

impl Read for Reader:
    fn read(value: Int?) Int: value.get(0) + self.offset

type Counter:
    calls: Int

fn next(var counter: Counter) Int:
    counter.calls += 1
    return counter.calls

fn ordered(first: Int?, second: Int?) Int:
    return first.get() * 10 + second.get()

fn invoke(value: (fn(Int) Int)?) Int: value.get()(4)

fn increment(value: Int) Int: value + 1

fn calls_of(value: Counter?) Int: value.get().calls

test "plain values and explicit optionals share the call contract":
    expect_equal(number(4), 4)?
    expect_equal(number(value: 0), 0)?

    supplied: Int? := 4
    expect_equal(number(supplied), 4)?
    expect_equal(number(), -1)?
    expect_equal(number(), -1)?

    stored: fn(Int?) Int := number
    expect_equal(stored(5), 5)?
    expect_equal(present(6).get(), 6)?
    expect_equal(present[Int](7).get(), 7)?

    generic_supplied: Int? := 8
    expect_equal(present(generic_supplied).get(), 8)?

    missing: Int? := none
    expect_false(not (nested(missing)))?

    outer: Int?? := missing
    expect_false(not (nested(outer)))?
    expect_equal(list_size([]), 0)?
    expect_equal(list_size([1, 2]), 2)?
    expect_equal(context(value: none, fallback: 9), 9)?
    expect_equal(context(value: [], fallback: [1]).length(), 0)?
    expect_equal(success(ok(10)), 10)?
    expect_false(flag(false))?
    expect_false(flag(true and false))?
    expect_equal(invoke(increment), 5)?
    expect_equal(invoke(fn value: value + 2), 6)?

test "constructor fields and methods use optional arguments":
    defaulted := DefaultBox()
    expect_false(not (defaulted.value.is_none()))?

    supplied := DefaultBox(3)
    expect_equal(supplied.value.get(), 3)?

    box := Box(4)
    expect_equal(box.value.get(), 4)?

    choice := Choice.chosen(5)

    match choice:
        chosen(value):
            expect_equal(value.get(), 5)?

    reader := Reader(2)
    expect_equal(reader.read(3), 5)?

    read := reader.read
    expect_equal(read(4), 6)?

    view: Read := reader
    expect_equal(view.read(5), 7)?

    counter := Counter(9)
    expect_equal(calls_of(counter.clone()), 9)?
    expect_equal(counter.calls, 9)?

    notice := Notice(Error("detail"))
    expect_equal(notice.failure.get().message, "detail")?

test "wrapping evaluates arguments once in written order":
    var counter = Counter(0)
    expect_equal(ordered(second: next(var counter), first: next(var counter)), 21)?
    expect_equal(counter.calls, 2)?

test "queue capacity accepts a plain value or omission":
    var bounded = Queue[Int](4)
    for value in [1, 2, 3, 4]:
        expect_false(not (bounded.enqueue(value)))?
    expect_false(bounded.enqueue(5))?
    expect_equal(bounded.dequeue().get(), 1)?

    var unbounded = Queue[Int]()
    var absent = Queue[Int]()
    capacity: Int? := 4
    var explicit = Queue[Int](capacity)

    for value in [1, 2, 3, 4, 5]:
        expect_false(not (unbounded.enqueue(value)))?
        expect_false(not (absent.enqueue(value)))?

    expect_false(not (explicit.enqueue(1)))?
