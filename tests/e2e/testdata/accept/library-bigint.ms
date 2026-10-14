import panic from "@std/faults.ms"

import parse from "@std/bigint.ms"

import BigInt from "@std/bigint.ms"
import Result from "@std/result.ms"
import BigIntError from "@std/bigint.ms"

fn verify_bigint() -> Result[Unit, BigIntError]:
    let large = try parse(text: "18446744073709551616", radix: 10, max_digits: 30)
    if not (
        ((large).multiply(other: large)).to_string(
            radix: 10
        ) == "340282366920938463463374607431768211456"
    ):
        return panic(message: "check failed")

    return ok(unit)

test "large integers are exact":
    let expected: Result[Unit, BigIntError] = ok(unit)
    if not (verify_bigint() == expected):
        return panic(message: "check failed")
