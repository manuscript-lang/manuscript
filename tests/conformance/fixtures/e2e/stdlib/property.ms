# conform: tags=closures,generics,lists,stdlib-property,stdlib-testing,testing,tier-io,try-result
# conform: phase=test
import (
    check,
    ints,
    bools,
    lists,
    strings,
    optionals,
    pairs,
    floats,
    element_of,
    one_of,
    constant
) from "@std/test/property.ms"
import panic from "@std/core.ms"
import expect_equal, expect_true, expect_contains, expect_error from "@std/test.ms"

test "a true property passes":
    try check(
        "reverse twice", lists(ints(-100, 100)),
        fn xs: expect_equal(xs.reversed().reversed(), xs)
    )

test "a failing list property shrinks to the smallest list":
    let cause = try expect_error(
        check(
            "small sums", lists(ints(0, 1000)), fn xs: expect_true(xs.sum() < 50),
            seed: 11
        )
    )
    try expect_contains(cause.message(), "counterexample: [50]")

test "a failing integer property shrinks toward the boundary":
    let cause = try expect_error(
        check(
            "below ten", ints(-1000, 1000), fn n: expect_true(n < 10), seed: 3
        )
    )
    try expect_contains(cause.message(), "counterexample: 10\n")

test "negative values shrink toward zero":
    let cause = try expect_error(
        check(
            "above minus ten", ints(-1000, 1000), fn n: expect_true(n > -10), seed: 5
        )
    )
    try expect_contains(cause.message(), "counterexample: -10\n")

test "strings shrink to the offending character":
    let cause = try expect_error(
        check(
            "no z", strings("abz", 12), fn s: expect_true(not s.contains("z")), seed: 2
        )
    )
    try expect_contains(cause.message(), "counterexample: z\n")

test "pairs shrink both components":
    let cause = try expect_error(
        check(
            "small pair sum", pairs(ints(-50, 50), ints(-50, 50)),
            fn p: expect_true(p.first + p.second < 10), seed: 1
        )
    )
    try expect_contains(cause.message(), "counterexample: Pair(first: ")

test "optionals shrink toward the failing payload":
    let cause = try expect_error(
        check(
            "below seven", optionals(ints(0, 100)), fn o: expect_true(o.get(0) < 7),
            seed: 9
        )
    )
    try expect_contains(cause.message(), "counterexample: Optional.some(7)")

test "filtered generators only produce kept values":
    try check(
        "even", ints(0, 1000).filter(fn n: n % 2 == 0), fn n: expect_equal(n % 2, 0)
    )

test "zip and flat_map compose generators":
    let sums = ints(0, 9).zip(ints(0, 9), fn a, b: a + b)
    try check("sum bound", sums, fn n: expect_true(n >= 0 and n <= 18))

    let sized = ints(1, 3).flat_map(fn n: lists(ints(0, 9), n, n))
    try check(
        "length follows the drawn size", sized,
        fn xs: expect_true(xs.length() >= 1 and xs.length() <= 3)
    )

test "mapped, one_of, element_of, constant, floats and bools compose":
    let doubled = ints(0, 10).map(fn n: n * 2)
    try check("doubled is even", doubled, fn n: expect_equal(n % 2, 0))
    try check(
        "choice", one_of([constant(1), constant(2)]),
        fn n: expect_true(n == 1 or n == 2)
    )
    try check(
        "element", element_of(["a", "b"]), fn s: expect_true(s == "a" or s == "b")
    )
    try check(
        "unit interval", floats(0.0, 1.0), fn f: expect_true(f >= 0.0 and f <= 1.0)
    )
    try check("bool", bools(), fn b: expect_true(b or not b))

test "the same seed reproduces the same failure":
    let first = try expect_error(
        check(
            "seeded", lists(ints(0, 100)), fn xs: expect_true(xs.length() < 3), seed: 42
        )
    )
    let second = try expect_error(
        check(
            "seeded", lists(ints(0, 100)), fn xs: expect_true(xs.length() < 3), seed: 42
        )
    )
    try expect_equal(first.message(), second.message())
    try expect_contains(first.message(), "counterexample: [0, 0, 0]")

test "a fault inside a property shrinks like an error":
    let cause = try expect_error(
        check("no big values", ints(0, 1000), fn n: faults_at(n, 100), seed: 4)
    )
    try expect_contains(cause.message(), "counterexample: 100\n")
    try expect_contains(cause.message(), "fault:")

fn faults_at(n: Int, limit: Int) Unit!:
    if n >= limit:
        panic("too big")
    return ok(unit)
