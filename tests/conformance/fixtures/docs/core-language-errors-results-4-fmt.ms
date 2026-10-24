# conform: tags=decimal,formatter,modules,optional,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/results.md:75
from "@std/core.ms" import TextError

def successful_price(outcome: Result[Decimal, TextError]) -> Optional[Decimal]:
    return outcome.to_optional()
