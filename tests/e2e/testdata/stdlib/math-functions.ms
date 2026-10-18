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
import panic from "@std/faults.ms"

fn near(actual: Float, expected: Float) Bool:
    return abs(actual - expected) < 0.000000001

test "inverse trigonometric functions return radians":
    if not near(acos(1.0), 0.0): return panic("acos 1")
    if not near(acos(0.0), pi() / 2.0): return panic("acos 0")
    if not near(asin(1.0), pi() / 2.0): return panic("asin 1")
    if not near(asin(0.0), 0.0): return panic("asin 0")
    if not near(atan(1.0), pi() / 4.0): return panic("atan 1")
    if not near(atan2(1.0, 1.0), pi() / 4.0): return panic("atan2 first quadrant")
    if not near(atan2(1.0, -1.0), 3.0 * pi() / 4.0): return panic(
        "atan2 second quadrant"
    )

test "tangent hyperbolic exponential and logarithm functions":
    if not near(tan(0.0), 0.0): return panic("tan 0")
    if not near(tan(pi() / 4.0), 1.0): return panic("tan quarter pi")
    if not near(sinh(0.0), 0.0): return panic("sinh 0")
    if not near(cosh(0.0), 1.0): return panic("cosh 0")
    if not near(tanh(0.0), 0.0): return panic("tanh 0")
    if not near(tanh(1.0), 0.7615941559557649): return panic("tanh 1")
    if not near(exp(0.0), 1.0): return panic("exp 0")
    if not near(exp(1.0), e()): return panic("exp 1")
    if not near(log10(1000.0), 3.0): return panic("log10 1000")

test "float remainder takes the sign of the dividend":
    if remainder(5.0, 3.0) != 2.0: return panic("remainder positive")
    if remainder(-5.0, 3.0) != -2.0: return panic("remainder negative")
    if remainder(7.0, 2.0) != 1.0: return panic("remainder half")
    if not remainder(5.0, 0.0).is_nan(): return panic("remainder zero divisor")

type Ranked:
    rank: Int

impl Comparable for Ranked:
    fn compare(other: Comparable) Int:
        match other:
            Ranked(value):
                if self.rank < value.rank: return -9223372036854775808
                if self.rank > value.rank: return 9223372036854775807

                return 0
            _: return panic("incompatible comparison")

test "extrema use comparator signs without negating Int minimum":
    let low = Ranked(1)
    let high = Ranked(2)
    if min(high, low).rank != 1: return panic("pair minimum")
    if max(low, high).rank != 2: return panic("pair maximum")

    for values in [[high, low], [low, high]]:
        if min_of(values).get().rank != 1: return panic("list minimum")
        if max_of(values).get().rank != 2: return panic("list maximum")

    let second_low = Ranked(1)
    let second_high = Ranked(2)
    let values = [high, low, second_low, second_high]
    let minimum = min_of(values).get()
    let maximum = max_of(values).get()
    minimum.rank = 0
    maximum.rank = 3
    if low.rank != 0 or second_low.rank != 1: return panic("first equal minimum")
    if high.rank != 3 or second_high.rank != 2: return panic("first equal maximum")
