# conform: tags=decimal,faults,formatter,modules,parser,stdlib-decimal,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/runtime-1.ms
import expect_equal from "@std/test/test.ms"
import Decimal from "@std/math/decimal.ms"

fn amount() Decimal!Error:
    return ok(12.50d)

test "explicit standard imports":
    try expect_equal([1, 2].length(), 2)
    try expect_equal(amount().get(0.0d), 12.50d)
