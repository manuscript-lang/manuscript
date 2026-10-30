# conform: tags=decimal,formatter,modules,optional,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:75
import TextError from "@std/core.ms"

fn successful_price(outcome: Result[Decimal, TextError]) Decimal?:
    return outcome.to_optional()
