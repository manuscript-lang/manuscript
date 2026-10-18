import {expect_false} from "@std/testing.ms"
import parse from "@std/bigint.ms"
import BigInt from "@std/bigint.ms"
import BigIntError from "@std/bigint.ms"

fn verify_bigint() -> Result[Unit, Error]:
    let large = try parse(text: "18446744073709551616", radix: 10, max_digits: 30)
    (
        not (
            ((large).multiply(other: large)).to_string(
                radix: 10
            ) == "340282366920938463463374607431768211456"
        )
    ) | try expect_false
    return ok(unit)

test "large integers are exact":
    try verify_bigint()
