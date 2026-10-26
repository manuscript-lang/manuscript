# conform: tags=closures,generics,lists,stdlib-property,stdlib-testing,testing,tier-io,try-result
# conform: phase=test
from "@std/test/property.ms" import check, ints, bools, lists, strings, optionals, pairs, filtered, floats, element_of, mapped, one_of, constant
from "@std/testing.ms" import expect_equal, expect_true, expect_contains, expect_error

test "a true property passes":
    try check(
        "reverse twice", lists(ints(-100, 100)),
        lambda xs: expect_equal(xs.reversed().reversed(), xs)
    )

test "a failing list property shrinks to the smallest list":
    let cause = try expect_error(
        check(
            "small sums", lists(ints(0, 1000)), lambda xs: expect_true(xs.sum() < 50),
            seed: 11
        )
    )
    try expect_contains(cause.message(), "counterexample: [50]")

test "a failing integer property shrinks toward the boundary":
    let cause = try expect_error(
        check(
            "below ten", ints(-1000, 1000), lambda n: expect_true(n < 10), seed: 3
        )
    )
    try expect_contains(cause.message(), "counterexample: 10\n")

test "negative values shrink toward zero":
    let cause = try expect_error(
        check(
            "above minus ten", ints(-1000, 1000), lambda n: expect_true(n > -10),
            seed: 5
        )
    )
    try expect_contains(cause.message(), "counterexample: -10\n")

test "strings shrink to the offending character":
    let cause = try expect_error(
        check(
            "no z", strings("abz", 12), lambda s: expect_true(not s.contains("z")),
            seed: 2
        )
    )
    try expect_contains(cause.message(), "counterexample: z\n")

test "pairs shrink both components":
    let cause = try expect_error(
        check(
            "small pair sum", pairs(ints(-50, 50), ints(-50, 50)),
            lambda p: expect_true(p.first + p.second < 10), seed: 1
        )
    )
    try expect_contains(cause.message(), "counterexample: Pair(first: ")

test "optionals shrink toward the failing payload":
    let cause = try expect_error(
        check(
            "below seven", optionals(ints(0, 100)), lambda o: expect_true(o.get(0) < 7),
            seed: 9
        )
    )
    try expect_contains(cause.message(), "counterexample: Optional.some(7)")

test "filtered generators only produce kept values":
    try check(
        "even", filtered(ints(0, 1000), lambda n: n % 2 == 0),
        lambda n: expect_equal(n % 2, 0)
    )

test "mapped, one_of, element_of, constant, floats and bools compose":
    let doubled = mapped(ints(0, 10), lambda n: n * 2)
    try check("doubled is even", doubled, lambda n: expect_equal(n % 2, 0))
    try check(
        "choice", one_of([constant(1), constant(2)]),
        lambda n: expect_true(n == 1 or n == 2)
    )
    try check(
        "element", element_of(["a", "b"]), lambda s: expect_true(s == "a" or s == "b")
    )
    try check(
        "unit interval", floats(0.0, 1.0), lambda f: expect_true(f >= 0.0 and f <= 1.0)
    )
    try check("bool", bools(), lambda b: expect_true(b or not b))

test "the same seed reproduces the same failure":
    let first = try expect_error(
        check(
            "seeded", lists(ints(0, 100)), lambda xs: expect_true(xs.length() < 3),
            seed: 42
        )
    )
    let second = try expect_error(
        check(
            "seeded", lists(ints(0, 100)), lambda xs: expect_true(xs.length() < 3),
            seed: 42
        )
    )
    try expect_equal(first.message(), second.message())
    try expect_contains(first.message(), "counterexample: [0, 0, 0]")
