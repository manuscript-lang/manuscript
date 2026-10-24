# conform: tags=control-flow,diagnostics,interpolation,records,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/syntax.md:12
export type Customer:
    name: String
    active: Bool

export def welcome(customer: Customer) -> String:
    if customer.active:
        return f"Welcome, {customer.name}!"

    return "Your account is inactive."
