# conform: tags=control-flow,faults,generics,interfaces,interpolation,lists,match,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/result-argument-inference.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

type Failure:
    code: Int

fn erase[T, E](r: Result[T, E]) Result[T, E]: r

fn optional[T](r: T!?) T!: r.get().clone()

fn same[T, E](r: T!E) T!E: r

fn both[T, E](cause: E, r: T!E) T!E: r

fn number() Int!Failure: ok(7)

type Events:
    values: List[Int]

fn record(var events: Events, value: Int) Int!:
    events.values.append(value)
    return ok(value)

fn default_value(var events: Events) Int:
    events.values.append(3)
    return 3

fn ordered[T](
    first: T!,
    second: T!,
    var events: Events,
    last: Int = default_value(events)
) T!:
    events.values.append(4)
    return first

test "infer success and error types from Result arguments":
    let r: Int! = error(Error("eleven", kind: ErrorCategory.InvalidData))
    let inferred = erase(r)
    let explicit = erase[Int, Error](r)
    let wrapped = optional(r)
    let known = Error("five")
    let inferred_from_known = both(known, r)

    for value in [
        inferred.clone(), explicit.clone(), wrapped, inferred_from_known.clone()
    ]:
        try expect_false(not value.is_error())
        try expect_equal(value.err().message, "eleven")
        try expect_equal(value.err().kind, ErrorCategory.InvalidData)

    let generic: Result[Int, Failure] = error(Failure(31))
    let failed = erase(generic)
    try expect_false(not failed.is_error())
    try expect_equal(failed.err().code, 31)

test "nested success preserves its domain and inferred errors remain exact":
    let inner: Int!Failure = error(Failure(41))
    let outer: Result[Int!Failure, Failure] = ok(inner)
    let value = erase(outer).get()
    try expect_false(not value.is_error())
    try expect_equal(value.err().code, 41)

    let exact = same(inner)
    try expect_false(not exact.is_error())
    try expect_equal(exact.err().code, 41)

    if let seven = erase(number()):
        try expect_equal(seven, 7)
    else:
        return fail("changed success case")

test "inference evaluates once in written order before defaults":
    var events = Events([])
    let result = ordered(
        second: record(var events, 2), first: record(var events, 1), var events
    )
    try expect_equal(events.values, [2, 1, 3, 4])

    let value = try result
    try expect_equal(value, 1)
