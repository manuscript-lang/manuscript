# conform: tags=closures,control-flow,formatter,generics,interfaces,match,modules,mutation,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/interface-view-callables.ms
import expect_equal from "@std/test.ms"

interface Read[T]:
    fn read() T

type Reader[T]:
    operation: fn() T

impl Read[T] for Reader[T]:
    fn read() T:
        return self.operation()

type Log:
    events: String

fn mark(var log: Log, event: String, value: Int) Int:
    log.events += event
    return value

fn prepare(var log: Log, value: Int) fn() Int:
    mark(var log, "prepare;", 0)
    return fn() Int:
        return value

fn wrap[T](operation: fn() T) Read[T]:
    return Reader[T](operation)

fn invoke[T: Read[Int]](value: T) Int:
    return value.read()

type OrderedReader:
    first: Int
    operation: fn() Int
    last: Int

impl Read[Int] for OrderedReader:
    fn read() Int:
        return self.first + self.operation() + self.last

type DefaultReader:
    base: Int
    operation: fn() Int = fn() Int: base

impl Read[Int] for DefaultReader:
    fn read() Int:
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
            fn() Int:
                let nested = fn() Int: value
                return nested()
        ),
        match some(2):
            some(number):
                value = 70
                mark(var log, "first;", number)
            none: 0
    )

    value = 90
    try expect_equal(log.events, "last;first;")
    try expect_equal(view.read(), 9)

test "explicit nested views and bound methods retain generic dispatch":
    var value = 5

    let view = wrap(
        fn() Int:
            let nested = fn() Int: value
            return nested()
    )

    value = 80

    let bound = view.read
    try expect_equal(bound(), 5)
    try expect_equal(invoke(view), 5)
    try expect_equal(Reader(fn() Int: 6).read(), 6)
    try expect_equal(Reader(fn() Int: 8).read(), 8)
    try expect_equal(wrap(fn() String: "text").read(), "text")

test "source constructors with callable defaults prepare once":
    var log = Log("")
    let view: Read[Int] = DefaultReader(mark(var log, "base;", 12))
    try expect_equal(log.events, "base;")
    try expect_equal(view.read(), 12)

test "match receiver side effects and callable body remain ordered":
    var log = Log("")

    let view: Read[Int] = match some(mark(var log, "select;", 1)):
        some(_):
            mark(var log, "chosen;", 0)
            Reader(fn() Int: 9)
        none:
            mark(var log, "wrong;", 0)
            Reader(fn() Int: 0)

    try expect_equal(log.events, "select;chosen;")
    try expect_equal(view.read(), 9)
