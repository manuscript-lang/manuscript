import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"

fn quotient(value: Int, divisor: Int) Int:
    return value / divisor

fn remainder(value: Int, divisor: Int) Int:
    return value % divisor

test "numeric boundary rules":
    if not (quotient(-7, 2) == -3):
        return panic("check failed")
    if not (remainder(-7, 3) == -1):
        return panic("check failed")
    if not (remainder(-9223372036854775808, -1) == 0):
        return panic("check failed")

    let infinity = 1.0 / 0.0
    let nan = 0.0 / 0.0
    if not ("{infinity}" == "Infinity"):
        return panic("check failed")
    if not (nan != nan):
        return panic("check failed")

    let third = 1d / 3d
    if not ("{third}" == "0.3333333333333333333333333333333333"):
        return panic("check failed")

    let absent: Optional[Int] = none
    if not (1e300.truncate_to_int() == absent):
        return panic("check failed")
    if not ((2.seconds + 1.seconds) == 3.seconds):
        return panic("check failed")
