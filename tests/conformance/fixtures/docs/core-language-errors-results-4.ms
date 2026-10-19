# conform: tags=decimal,diagnostics,modules,optional,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/errors/results.md:75
import {TextError} from "@std/errors.ms"
fn successful_price(outcome: Result[Decimal, TextError]) Optional[Decimal]:
    return outcome.to_optional()
