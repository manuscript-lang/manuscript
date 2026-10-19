# conform: tags=decimal,faults,modules,stdlib-decimal,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/runtime-1.ms
import {TextError} from "@std/errors.ms"
import {expect_equal} from "@std/testing.ms"
import Decimal from "@std/decimal.ms"

fn amount() Result[Decimal, TextError]:
    return ok(12.50d)

test "explicit standard imports":
    try expect_equal([1, 2].length(), 2)
    try expect_equal(amount().get(0.0d), 12.50d)
