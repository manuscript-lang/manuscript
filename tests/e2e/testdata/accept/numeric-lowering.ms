import panic from "@std/faults.ms"

type Counter:
    value: Int

fn step(counter: Counter, value: Int) Int:
    counter.value = counter.value * 10 + value
    return value

fn identity[T](value: T) T:
    return value

test "typed operands retain evaluation order and generic boundaries":
    let counter = Counter(0)
    let total = (step(counter, 1) + step(counter, 2) * step(counter, 3))
    if total != 7 or counter.value != 123: return panic("operand order")

    var value = identity(9)
    value += 1
    let snapshot = fn() Int: return value * 2
    value -= 1
    if snapshot() != 20 or value != 9: return panic("boxed capture")
    if - 9223372036854775808 % -1 != 0: return panic("minimum remainder")
    if - 7 / 2 != -3 or - 7 % 3 != -1: return panic("signed arithmetic")
    if 9223372036854775807 * 0 != 0: return panic("zero multiplication")

test "unary plus keeps the operand":
    let count = 4
    let ratio = 2.5
    if + count != 4 or + + count != 4 or + ratio != 2.5 or 3 - + count != -1: return panic(
        "unary plus"
    )

test "floating operations retain binary64 edge behavior":
    let negative_zero = -0.0
    if "{1.0 / negative_zero}" != "-Infinity": return panic("signed zero")

    let nan = 0.0 / 0.0
    if (nan <= 0.0 or nan >= 0.0 or nan < 0.0 or nan > 0.0): return panic(
        "NaN comparisons"
    )
    if 5e-324 <= 0.0 or 5e-324 / 2.0 != 0.0: return panic("subnormal rounding")
    if "{1.7976931348623157e308 * 2.0}" != "Infinity": return panic("floating overflow")

    let a = 1.0000000074505806
    let b = 0.9999999925494194
    if a * b - 1.0 != 0.0: return panic("per-operation rounding")
