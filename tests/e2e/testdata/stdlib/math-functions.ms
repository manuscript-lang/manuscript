import {expect_equal, expect_false} from "@std/testing.ms"
import {
    acos,
    asin,
    atan,
    atan2,
    cosh,
    exp,
    log10,
    sinh,
    tan,
    tanh,
    abs,
    pi,
    e,
    remainder,
    max,
    min,
    max_of,
    min_of
} from "@std/math.ms"

fn near(actual: Float, expected: Float) Bool:
    return abs(actual - expected) < 0.000000001

test "inverse trigonometric functions return radians":
    try expect_false(not near(acos(1.0), 0.0))
    try expect_false(not near(acos(0.0), pi() / 2.0))
    try expect_false(not near(asin(1.0), pi() / 2.0))
    try expect_false(not near(asin(0.0), 0.0))
    try expect_false(not near(atan(1.0), pi() / 4.0))
    try expect_false(not near(atan2(1.0, 1.0), pi() / 4.0))
    try expect_false(not near(atan2(1.0, -1.0), 3.0 * pi() / 4.0))

test "tangent hyperbolic exponential and logarithm functions":
    try expect_false(not near(tan(0.0), 0.0))
    try expect_false(not near(tan(pi() / 4.0), 1.0))
    try expect_false(not near(sinh(0.0), 0.0))
    try expect_false(not near(cosh(0.0), 1.0))
    try expect_false(not near(tanh(0.0), 0.0))
    try expect_false(not near(tanh(1.0), 0.7615941559557649))
    try expect_false(not near(exp(0.0), 1.0))
    try expect_false(not near(exp(1.0), e()))
    try expect_false(not near(log10(1000.0), 3.0))

test "float remainder takes the sign of the dividend":
    try expect_equal(remainder(5.0, 3.0), 2.0)
    try expect_equal(remainder(-5.0, 3.0), -2.0)
    try expect_equal(remainder(7.0, 2.0), 1.0)
    try expect_false(not remainder(5.0, 0.0).is_nan())

type Ranked:
    rank: Int
    unexpected: List[Int] = []

impl Comparable for Ranked:
    fn compare(other: Comparable) Int:
        match other:
            Ranked(value):
                if self.rank < value.rank: return -9223372036854775808
                if self.rank > value.rank: return 9223372036854775807

                return 0
            _:
                self.unexpected.append(1)
                return 0

test "extrema use comparator signs without negating Int minimum":
    let low = Ranked(1)
    let high = Ranked(2)
    try expect_equal(min(high, low).rank, 1)
    try expect_equal(max(low, high).rank, 2)

    for values in [[high, low], [low, high]]:
        try expect_equal(min_of(values).get().rank, 1)
        try expect_equal(max_of(values).get().rank, 2)

    let second_low = Ranked(1)
    let second_high = Ranked(2)
    let values = [high, low, second_low, second_high]
    let minimum = min_of(values).get()
    let maximum = max_of(values).get()
    minimum.rank = 0
    maximum.rank = 3
    try expect_false(low.rank != 0 or second_low.rank != 1)
    try expect_false(high.rank != 3 or second_high.rank != 2)
    for value in [low, high, second_low, second_high]:
        try expect_false(not value.unexpected.is_empty())
