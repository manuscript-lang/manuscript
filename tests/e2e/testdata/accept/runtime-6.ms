import panic from "@std/faults.ms"

import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

fn quotient(value: Int, divisor: Int) -> Int:
    return value / divisor

fn remainder(value: Int, divisor: Int) -> Int:
    return value % divisor

test "numeric boundary rules":
    if not (quotient(value: -7, divisor: 2) == -3):
        return panic(message: "check failed")
    if not (remainder(value: -7, divisor: 3) == -1):
        return panic(message: "check failed")
    if not (remainder(value: -9223372036854775808, divisor: -1) == 0):
        return panic(message: "check failed")
    let infinity = 1.0 / 0.0
    let nan = 0.0 / 0.0
    if not ("{infinity}" == "Infinity"):
        return panic(message: "check failed")
    if not (nan != nan):
        return panic(message: "check failed")
    let third = 1d / 3d
    if not ("{third}" == "0.3333333333333333333333333333333333"):
        return panic(message: "check failed")
    let absent: Optional[Int] = none
    if not (1e300.truncate_to_int() == absent):
        return panic(message: "check failed")
    if not ((2.seconds + 1.seconds) == 3.seconds):
        return panic(message: "check failed")
