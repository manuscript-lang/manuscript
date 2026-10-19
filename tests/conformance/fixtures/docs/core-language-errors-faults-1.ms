# conform: tags=control-flow,decimal,diagnostics,faults,modules,stdlib-faults,tier-stdlib
# conform: phase=check
# conform: origin=documentation/core-language/errors/faults.md:14
import panic from "@std/faults.ms"

fn discount_validated(price: Decimal, percent: Decimal) Decimal:
    if price <= 0d:
        return panic("Price must be positive")
    if percent <= 0d or percent >= 100d:
        return panic("Percent must be positive and below 100")
    return price * (1d - percent / 100d)
