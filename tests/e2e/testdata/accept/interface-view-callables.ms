import panic from "@std/faults.ms"

interface Read[T]:
    fn read() -> T

type Reader[T]:
    operation: fn() -> T

impl Read[T] for Reader[T]:
    fn read() -> T:
        return self.operation()

type Log:
    events: String

fn mark(log: Log, event: String, value: Int) -> Int:
    log.events = log.events + event
    return value

fn prepare(log: Log, value: Int) -> fn() -> Int:
    mark(log, "prepare;", 0)
    return fn() -> Int:
        return mark(log, "call;", value)

fn wrap[T](operation: fn() -> T) -> Read[T]:
    return Read[T](Reader[T](operation))

fn invoke[T: Read[Int]](value: T) -> Int:
    return value.read()

type OrderedReader:
    first: Int
    operation: fn() -> Int
    last: Int

impl Read[Int] for OrderedReader:
    fn read() -> Int:
        return self.first + self.operation() + self.last

type DefaultReader:
    base: Int
    operation: fn() -> Int = fn() -> Int: base

impl Read[Int] for DefaultReader:
    fn read() -> Int:
        return self.operation()

test "nested view receiver prepares once and calls later":
    let log = Log("")
    let view = Read[Int](
        Reader(prepare(log, 7))
    )
    if log.events != "prepare;": return panic("receiver preparation count")
    if view.read() != 7: return panic("view result")
    if log.events != "prepare;call;": return panic("callable evaluation count/order")

test "constructor arguments retain written order and capture snapshots":
    let log = Log("")
    var value = 4
    let view = Read[Int](
        OrderedReader(
            last: mark(log, "last;", 3),
            operation: (
                fn() -> Int:
                    let nested = fn() -> Int: value
                    return mark(
                        log,
                        "call;",
                        nested()
                    )
            ),
            first: match some(2):
                some(number):
                    value = 70
                    mark(log, "first;", number)
                none: 0
        )
    )
    value = 90
    if log.events != "last;first;": return panic("constructor argument order")
    if view.read() != 9: return panic("nested capture changed")
    if log.events != "last;first;call;": return panic(
        "closure called during construction"
    )

test "explicit nested views and bound methods retain generic dispatch":
    var value = 5
    let view = wrap(
        fn() -> Int:
            let nested = fn() -> Int: value
            return nested()
    )
    value = 80
    let bound = view.read
    if bound() != 5: return panic("bound interface method")
    if invoke(view) != 5: return panic("bounded generic method")
    if Read[Int](
        Read[Int](
            Reader(
                fn() -> Int: 6
            )
        )
    ).read() != 6:
        return panic("nested explicit views")
    if Reader(
        fn() -> Int: 8
    ).read() != 8: return panic("concrete method")
    if wrap(
        fn() -> String: "text"
    ).read() != "text": return panic("generic result")

test "source constructors with callable defaults prepare once":
    let log = Log("")
    let view = Read[Int](
        DefaultReader(mark(log, "base;", 12))
    )
    if log.events != "base;": return panic("default constructor preparation count")
    if view.read() != 12: return panic("default callable capture")
    if log.events != "base;": return panic("default repeated supplied argument")

test "match receiver side effects and callable body remain ordered":
    let log = Log("")
    let view = Read[Int](
        match some(mark(log, "select;", 1)):
            some(value):
                mark(log, "chosen;", 0)
                Reader(
                    fn() -> Int: mark(log, "call;", 9)
                )
            none:
                mark(log, "wrong;", 0)
                Reader(
                    fn() -> Int: 0
                )
    )
    if log.events != "select;chosen;": return panic("match receiver count/order")
    if view.read() != 9: return panic("match view result")
    if log.events != "select;chosen;call;": return panic("match callback timing")
