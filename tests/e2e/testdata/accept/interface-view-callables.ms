from "@std/test.ms" import expect_equal

interface Read[T]:
    def read() -> T

type Reader[T]:
    operation: Callable[[], T]

impl Read[T] for Reader[T]:
    def read() -> T:
        return self.operation()

type Log:
    events: String

def mark(var log: Log, event: String, value: Int) -> Int:
    log.events += event
    return value

def prepare(var log: Log, value: Int) -> Callable[[], Int]:
    mark(var log, "prepare;", 0)
    return lambda () -> Int:
        return value

def wrap[T](operation: Callable[[], T]) -> Read[T]:
    return Reader[T](operation)

def invoke[T: Read[Int]](value: T) -> Int:
    return value.read()

type OrderedReader:
    first: Int
    operation: Callable[[], Int]
    last: Int

impl Read[Int] for OrderedReader:
    def read() -> Int:
        return self.first + self.operation() + self.last

type DefaultReader:
    base: Int
    operation: Callable[[], Int] = lambda () -> Int: base

impl Read[Int] for DefaultReader:
    def read() -> Int:
        return self.operation()

test "nested view receiver prepares once and calls later":
    var log = Log("")
    let view: Read[Int] = Reader(prepare(var log, 7))
    try expect_equal(log.events, "prepare;")
    try expect_equal(view.read(), 7)

test "constructor arguments retain written order and capture snapshots":
    var log = Log("")
    var value = 4

    let view: Read[Int] = OrderedReader(
        last: mark(var log, "last;", 3),
        operation: (
            lambda () -> Int:
                let nested = lambda () -> Int: value
                return nested()
        ),
        match some(2):
            case some(number):
                value = 70
                mark(var log, "first;", number)
            case none: 0
    )

    value = 90
    try expect_equal(log.events, "last;first;")
    try expect_equal(view.read(), 9)

test "explicit nested views and bound methods retain generic dispatch":
    var value = 5

    let view = wrap(
        lambda () -> Int:
            let nested = lambda () -> Int: value
            return nested()
    )

    value = 80

    let bound = view.read
    try expect_equal(bound(), 5)
    try expect_equal(invoke(view), 5)
    try expect_equal(Reader(lambda () -> Int: 6).read(), 6)
    try expect_equal(Reader(lambda () -> Int: 8).read(), 8)
    try expect_equal(wrap(lambda () -> String: "text").read(), "text")

test "source constructors with callable defaults prepare once":
    var log = Log("")
    let view: Read[Int] = DefaultReader(mark(var log, "base;", 12))
    try expect_equal(log.events, "base;")
    try expect_equal(view.read(), 12)

test "match receiver side effects and callable body remain ordered":
    var log = Log("")

    let view: Read[Int] = match some(mark(var log, "select;", 1)):
        case some(_):
            mark(var log, "chosen;", 0)
            Reader(lambda () -> Int: 9)
        case none:
            mark(var log, "wrong;", 0)
            Reader(lambda () -> Int: 0)

    try expect_equal(log.events, "select;chosen;")
    try expect_equal(view.read(), 9)
