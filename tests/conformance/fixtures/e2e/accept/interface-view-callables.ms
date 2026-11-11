// conform: tags=closures,control-flow,generics,interfaces,match,modules,mutation,optional,records,stdlib-testing,strings,testing,tier-core,try-result,scope-cleanup
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/interface-view-callables.ms
import expect_equal from "@std/test/test.ms"

interface Read[T]:
    fn read() T

type Reader[T]:
    operation: fn() T

fn Reader[T].read() T:
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

fn OrderedReader.read() Int:
    return self.first + self.operation() + self.last

type DefaultReader:
    base: Int
    operation: fn() Int = fn() Int: base

fn DefaultReader.read() Int:
    return self.operation()

test "nested view receiver prepares once and calls later":
    var log = Log("")
    view: Read[Int] := Reader(prepare(var log, 7))
    expect_equal(log.events, "prepare;")?
    expect_equal(view.read(), 7)?

test "constructor arguments retain written order and capture snapshots":
    var log = Log("")
    var value = 4
    snapshot := value

    view: Read[Int] := OrderedReader(
        last: mark(var log, "last;", 3),
        operation: (
            fn() Int:
                nested := fn() Int: snapshot
                return nested()
        ),
        match present(2):
            number:
                value = 70
                mark(var log, "first;", number)
            none: 0
    )

    value = 90
    expect_equal(log.events, "last;first;")?
    expect_equal(view.read(), 9)?

test "explicit nested views and bound methods retain generic dispatch":
    var value = 5
    snapshot := value

    view := wrap(
        fn() Int:
            nested := fn() Int: snapshot
            return nested()
    )

    value = 80

    bound := view.read
    expect_equal(bound(), 5)?
    expect_equal(invoke(view), 5)?
    expect_equal(Reader(fn() Int: 6).read(), 6)?
    expect_equal(Reader(fn() Int: 8).read(), 8)?
    expect_equal(wrap(fn() String: "text").read(), "text")?

test "source constructors with callable defaults prepare once":
    var log = Log("")
    view: Read[Int] := DefaultReader(mark(var log, "base;", 12))
    expect_equal(log.events, "base;")?
    expect_equal(view.read(), 12)?

test "match receiver side effects and callable body remain ordered":
    var log = Log("")

    view: Read[Int] := match present(mark(var log, "select;", 1)):
        _value:
            mark(var log, "chosen;", 0)
            Reader(fn() Int: 9)
        none:
            mark(var log, "wrong;", 0)
            Reader(fn() Int: 0)

    expect_equal(log.events, "select;chosen;")?
    expect_equal(view.read(), 9)?

fn present[T](value: T) T?:
    return value
