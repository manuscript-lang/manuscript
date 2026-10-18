import {expect_equal, fail} from "@std/testing.ms"

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
            ok(_): return fail("expected error")
            error(view): view

        view.message() | try expect_equal(expected: "19")

        match view:
            Failure(original):
                original.code | try expect_equal(expected: 19)
                original.code = 23
            _: return fail("lost concrete error identity")

        cause.code | try expect_equal(expected: 23)
        cause.code = 19

    let generic: Result[Int, Tagged[Int]] = error(Tagged(31))

    let view = match erase(generic):
        ok(_): return fail("expected generic error")
        error(view): view

    view.message() | try expect_equal(expected: "tagged 31")

    match view:
        Tagged[Int](original):
            try expect_equal(original.value, 31)
        _: return fail("lost generic identity")

test "nested success preserves its domain and inferred errors remain exact":
    let inner: Result[Int, Failure] = error(Failure(41))
    let outer: Result[Result[Int, Failure], Tagged[Int]] = ok(inner)

    let value = match erase(outer):
        ok(value): value
        error(_): return fail("changed outer case")

    match value:
        ok(_): return fail("expected inner error")
        error(cause):
            try expect_equal(cause.code, 41)

    match same(inner):
        ok(_): return fail("expected exact error")
        error(cause):
            try expect_equal(cause.code, 41)

    match erase(number()):
        ok(value):
            try expect_equal(value, 7)
        error(_): return fail("changed success case")

test "inference and widening evaluate once in written order before defaults":
    let events = Events([])
    let result = ordered(
        second: record(events: events, value: 2),
        first: record(events: events, value: 1),
        events: events
    )
    events.values | try expect_equal(expected: [2, 1, 3, 4])

    match result:
        ok(value):
            try expect_equal(value, 1)
        error(_): return fail("changed result")
