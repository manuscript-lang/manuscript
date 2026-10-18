import panic from "@std/faults.ms"
import parse from "@std/bigint.ms"
import BigIntError from "@std/bigint.ms"

fn verify_bigint() Result[Unit, BigIntError]:
    let large = try parse("18446744073709551616", 10, 30)
    if not (
        ((large).multiply(large)).to_string_radix(
            10
        ) == "340282366920938463463374607431768211456"
    ):
        return panic("check failed")

    return ok(unit)

test "large integers are exact":
    let expected: Result[Unit, BigIntError] = ok(unit)
    if not (verify_bigint() == expected):
        return panic("check failed")
