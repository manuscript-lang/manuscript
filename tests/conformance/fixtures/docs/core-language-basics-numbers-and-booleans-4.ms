// conform: tags=decimal,interpolation,modules,stdlib-decimal,stdlib-numbers,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=documentation/core-language/basics/numbers-and-booleans.md:114
import Decimal from "@std/math/decimal.ms"
import expect_equal from "@std/test/test.ms"

fn amount_text() Result[String, Error]:
    subtotal := 19.99d * 3d
    tax := (subtotal * 0.0825d).round(places: 2)?
    tax_text := tax.to_fixed(digits: 2)?
    total_text := (subtotal + tax).to_fixed(digits: 2)?
    padded := 25.50d.to_fixed(digits: 2)?
    return ok("tax {tax_text} total {total_text} padded {padded}")

test "decimal amounts":
    amount_text()? | expect_equal("tax 4.95 total 64.92 padded 25.50")?
