# conform: tags=decimal,interpolation,modules,stdlib-decimal,stdlib-numbers,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=documentation/core-language/basics/numbers-and-booleans.md:114
from "@std/decimal.ms" import Decimal
from "@std/math.ms" import NumberError
from "@std/test.ms" import expect_equal

def amount_text() -> Result[String, NumberError]:
    let subtotal = 19.99d * 3d
    let tax = try (subtotal * 0.0825d).round(places: 2)
    let tax_text = try tax.to_fixed(digits: 2)
    let total_text = try (subtotal + tax).to_fixed(digits: 2)
    let padded = try 25.50d.to_fixed(digits: 2)
    return ok(f"tax {tax_text} total {total_text} padded {padded}")

test "decimal amounts":
    try amount_text() | try expect_equal("tax 4.95 total 64.92 padded 25.50")
