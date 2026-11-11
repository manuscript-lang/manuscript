// conform: tags=modules,stdlib-bigint,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/library-bigint.ms
import expect_false from "@std/test/test.ms"
import parse from "@std/math/math.ms"
import BigInt from "@std/math/math.ms"

fn verify_bigint() Unit!:
    large := parse(text: "18446744073709551616", radix: 10, max_digits: 30)?
    (
        not (
            ((large).multiply(other: large)).to_string_radix(
                radix: 10
            ) == "340282366920938463463374607431768211456"
        )
    ) | expect_false?

test "large integers are exact":
    verify_bigint()?
