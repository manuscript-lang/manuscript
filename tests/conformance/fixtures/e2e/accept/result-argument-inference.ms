# conform: tags=control-flow,faults,generics,interfaces,interpolation,lists,match,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/result-argument-inference.ms
import expect_equal, expect_false, fail from "@std/test.ms"

type Failure:
    code: Int

impl Error for Failure:
    fn message() String: self.code.to_string()

type Tagged[T]:
    value: T

impl Error for Tagged[T]:
    fn message() String: "tagged {self.value}"

fn erase[T](r: T!) T!: r

fn forward[T, E: Error](r: T!E) T!: erase(r)

fn optional[T](r: T!?) T!: r.get().clone()

fn same[T, E: Error](r: T!E) T!E: r

fn both[T, E: Error](cause: E, r: T!E) T!E: r

fn number() Int!Failure: ok(7)

type Events:
    values: List[Int]

fn record(var events: Events, value: Int) Int!Failure:
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

test "infer success and preserve concrete error identity":
    let cause = Failure(11)
    let r: Int!Failure = error(cause)
    let inferred = erase(r)
    let explicit = erase[Int](r)
    let wrapped = optional(r)
    let forwarded = forward(r)
    let known: Error = Failure(5)
    let inferred_from_known = both(known, r)

    for value in [inferred, explicit, wrapped, forwarded, inferred_from_known]:
        try expect_false(not value.is_error())

        let view = value.err()
        try expect_equal(view.message(), "11")

        match view:
            Failure(original):
                try expect_equal(original.code, 11)
            _: return fail("lost concrete error identity")

    let generic: Result[Int, Tagged[Int]] = error(Tagged(31))
    let failed = erase(generic)
    try expect_false(not failed.is_error())

    let view = failed.err()
    try expect_equal(view.message(), "tagged 31")

    match view:
        Tagged[Int](original):
            try expect_equal(original.value, 31)
        _: return fail("lost generic identity")

test "nested success preserves its domain and inferred errors remain exact":
    let inner: Int!Failure = error(Failure(41))
    let outer: Result[Int!Failure, Tagged[Int]] = ok(inner)
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

test "inference and widening evaluate once in written order before defaults":
    var events = Events([])
    let result = ordered(
        second: record(var events, 2), first: record(var events, 1), var events
    )
    try expect_equal(events.values, [2, 1, 3, 4])

    let value = try result
    try expect_equal(value, 1)
