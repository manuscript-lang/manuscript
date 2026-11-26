// conform: tags=control-flow,diagnostics,formatter,interpolation,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/syntax.md:12
export type Customer {
	name String
	active Bool
}

export fn welcome(customer Customer) String {
	if customer.active {
		return f"Welcome, {customer.name}!"
	}
	return "Your account is inactive."
}
// expect-exit: 0
