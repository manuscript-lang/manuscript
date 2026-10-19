# conform: tags=control-flow,formatter,interpolation,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/syntax.md:12
export type Customer:
    name: String
    active: Bool

export fn welcome(customer: Customer) String:
    if customer.active:
        return "Welcome, {customer.name}!"

    return "Your account is inactive."
