# conform: tags=closures,control-flow,generics,interfaces,match,modules,mutation,optional,records,stdlib-testing,strings,testing,tier-core,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/interface-view-callables.ms
import {expect_equal} from "@std/testing.ms"

interface Read[T]:
    fn read() T

type Reader[T]:
    operation: fn() T

impl Read[T] for Reader[T]:
    fn read() T:
        return self.operation()

type Log:
    events: String

fn mark(log: Log, event: String, value: Int) Int:
    log.events += event
    return value

fn prepare(log: Log, value: Int) fn() Int:
    mark(log, "prepare;", 0)
    return fn() Int:
        return mark(log, "call;", value)

fn wrap[T](operation: fn() T) Read[T]:
    return Read[T](Reader[T](operation))

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
    let log = Log("")
    let view = Read[Int](Reader(prepare(log, 7)))
    try expect_equal(log.events, "prepare;")
    try expect_equal(view.read(), 7)
    try expect_equal(log.events, "prepare;call;")

test "constructor arguments retain written order and capture snapshots":
    let log = Log("")
    var value = 4
    let view = Read[Int](
        OrderedReader(
            last: mark(log, "last;", 3),
            operation: (
                fn() Int:
                    let nested = fn() Int: value
                    return mark(log, "call;", nested())
            ),
            match some(2):
                some(number):
                    value = 70
                    mark(log, "first;", number)
                none: 0
        )
    )
    value = 90
    try expect_equal(log.events, "last;first;")
    try expect_equal(view.read(), 9)
    try expect_equal(log.events, "last;first;call;")

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
    try expect_equal(Read[Int](Read[Int](Reader(fn() Int: 6))).read(), 6)
    try expect_equal(Reader(fn() Int: 8).read(), 8)
    try expect_equal(wrap(fn() String: "text").read(), "text")

test "source constructors with callable defaults prepare once":
    let log = Log("")
    let view = Read[Int](DefaultReader(mark(log, "base;", 12)))
    try expect_equal(log.events, "base;")
    try expect_equal(view.read(), 12)
    try expect_equal(log.events, "base;")

test "match receiver side effects and callable body remain ordered":
    let log = Log("")
    let view = Read[Int](
        match some(mark(log, "select;", 1)):
            some(_):
                mark(log, "chosen;", 0)
                Reader(fn() Int: mark(log, "call;", 9))
            none:
                mark(log, "wrong;", 0)
                Reader(fn() Int: 0)
    )
    try expect_equal(log.events, "select;chosen;")
    try expect_equal(view.read(), 9)
    try expect_equal(log.events, "select;chosen;call;")
