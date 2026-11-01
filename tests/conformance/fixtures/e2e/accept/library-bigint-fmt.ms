# conform: tags=formatter,modules,parser,stdlib-bigint,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/library-bigint.ms
import expect_false from "@std/test/test.ms"
import parse from "@std/math/math.ms"
import BigInt from "@std/math/math.ms"
import BigIntError from "@std/math/math.ms"

fn verify_bigint() Unit!:
    let large = try parse(text: "18446744073709551616", radix: 10, max_digits: 30)
    (
        not (
            ((large).multiply(other: large)).to_string_radix(
                radix: 10
            ) == "340282366920938463463374607431768211456"
        )
    ) | try expect_false
    return ok(unit)

test "large integers are exact":
    try verify_bigint()
