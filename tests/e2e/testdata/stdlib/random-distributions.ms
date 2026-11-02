import seeded from "@std/os/random.ms"
import expect_equal, expect_true from "@std/test/test.ms"

test "seeded distributions repeat for equal seeds":
    var left = seeded(7)
    var right = seeded(7)
    try expect_equal(left.normal(), right.normal())
    try expect_equal(left.exponential(), right.exponential())
    try expect_equal(left.permutation(10), right.permutation(10))

test "normal samples centre on zero with unit spread":
    var rng = seeded(1)
    var sum = 0.0
    var squares = 0.0

    for ignored in 0..20000:
        let value = rng.normal()
        sum += value
        squares += value * value

    try expect_true(sum / 20000.0 > -0.05 and sum / 20000.0 < 0.05)
    try expect_true(squares / 20000.0 > 0.95 and squares / 20000.0 < 1.05)

test "exponential samples are non-negative with mean one":
    var rng = seeded(2)
    var sum = 0.0

    for ignored in 0..20000:
        let value = rng.exponential()
        try expect_true(value >= 0.0)
        sum += value

    try expect_true(sum / 20000.0 > 0.95 and sum / 20000.0 < 1.05)

test "permutation contains each index once":
    var rng = seeded(3)
    let order = rng.permutation(50)
    var expected: List[Int] = []
    for index in 0..50:
        expected.append(index)
    try expect_equal(order.length(), 50)
    try expect_equal(order.sorted(), expected)
    try expect_equal(rng.permutation(0).length(), 0)
