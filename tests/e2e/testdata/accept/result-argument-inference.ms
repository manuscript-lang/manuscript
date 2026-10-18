import panic from "@std/faults.ms"

type Failure:
    code: Int

impl Error for Failure:
    fn message() -> String: self.code.toString()

type Tagged[T]:
    value: T

impl Error for Tagged[T]:
    fn message() -> String: "tagged {self.value}"

fn erase[T](r: Result[T, Error]) -> Result[T, Error]: r

fn forward[T, E: Error](r: Result[T, E]) -> Result[T, Error]: erase(r)

fn optional[T](r: Optional[Result[T, Error]]) -> Result[T, Error]: r.unwrap()

fn same[T, E](r: Result[T, E]) -> Result[T, E]: r

fn both[T, E](cause: E, r: Result[T, E]) -> Result[T, E]: r

fn number() -> Result[Int, Failure]: ok(7)

type Events:
    values: List[Int]

fn record(events: Events, value: Int) -> Result[Int, Failure]:
    events.values = events.values.append(value)
    return ok(value)

fn default_value(events: Events) -> Int:
    events.values = events.values.append(3)
    return 3

fn ordered[T](
    first: Result[T, Error],
    second: Result[T, Error],
    events: Events,
    last: Int = default_value(events)
) -> Result[T, Error]:
    events.values = events.values.append(4)
    return first

test "infer success and preserve concrete error identity":
    let cause = Failure(11)
    let r: Result[Int, Failure] = error(cause)
    let inferred = erase(r)
    let explicit = erase[Int](r)
    let wrapped = optional(r)
    let forwarded = forward(r)
    let known: Error = Failure(5)
    let inferred_from_known = both(cause: known, r: r)
    cause.code = 19

    for value in [inferred, explicit, wrapped, forwarded, inferred_from_known]:
        let view = match value:
            ok(_): return panic("expected error")
            error(view): view

        if view.message() != "19": return panic("lost Error dispatch")

        match view:
            Failure(original):
                if original.code != 19: return panic("copied domain error")

                original.code = 23
            _: return panic("lost concrete error identity")

        if cause.code != 23: return panic("lost receiver alias")

        cause.code = 19

    let generic: Result[Int, Tagged[Int]] = error(Tagged(31))

    let view = match erase(generic):
        ok(_): return panic("expected generic error")
        error(view): view

    if view.message() != "tagged 31": return panic("lost generic Error evidence")

    match view:
        Tagged[Int](original):
            if original.value != 31: return panic("lost generic payload")
        _: return panic("lost generic identity")

test "nested success preserves its domain and inferred errors remain exact":
    let inner: Result[Int, Failure] = error(Failure(41))
    let outer: Result[Result[Int, Failure], Tagged[Int]] = ok(inner)

    let value = match erase(outer):
        ok(value): value
        error(_): return panic("changed outer case")

    match value:
        ok(_): return panic("expected inner error")
        error(cause):
            if cause.code != 41: return panic("changed nested success error")

    match same(inner):
        ok(_): return panic("expected exact error")
        error(cause):
            if cause.code != 41: return panic("inferred Error instead of Failure")

    match erase(number()):
        ok(value):
            if value != 7: return panic("changed success")
        error(_): return panic("changed success case")

test "inference and widening evaluate once in written order before defaults":
    let events = Events([])
    let result = ordered(
        second: record(events: events, value: 2),
        first: record(events: events, value: 1),
        events: events
    )
    if events.values != [2, 1, 3, 4]: return panic("changed evaluation order")

    match result:
        ok(value):
            if value != 1: return panic("changed parameter binding")
        error(_): return panic("changed result")
