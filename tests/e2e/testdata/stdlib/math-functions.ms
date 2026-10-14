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
    e
} from "@std/math.ms"
import panic from "@std/faults.ms"

fn near(actual: Float, expected: Float) -> Bool:
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
