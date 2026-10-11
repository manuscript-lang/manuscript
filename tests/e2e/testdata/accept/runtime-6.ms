import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

fn quotient(value: Int, divisor: Int) -> Int:
    return value / divisor

fn remainder(value: Int, divisor: Int) -> Int:
    return value % divisor

test "numeric boundary rules":
    assert quotient(value: -7, divisor: 2) == -3
    assert remainder(value: -7, divisor: 3) == -1
    assert remainder(value: -9223372036854775808, divisor: -1) == 0
    let infinity = 1.0 / 0.0
    let nan = 0.0 / 0.0
    assert "{infinity}" == "Infinity"
    assert nan != nan
    let third = 1d / 3d
    assert "{third}" == "0.3333333333333333333333333333333333"
    let absent: Optional[Int] = none
    assert 1e300.truncate_to_int() == absent
    assert (2.seconds + 1.seconds) == 3.seconds
