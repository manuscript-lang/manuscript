// conform: tags=control-flow,formatter,lists,mutation,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/modules/boundaries.md:12
export type Item {
	price Int
	quantity Int
}

export fn total(items List[Item]) Int {
	var result = 0
	for item in items {
		result += item.price * item.quantity
	}
	return result
}
// expect-format: rewritten
// expect-formatted: export type Item {
// expect-formatted: \tprice, quantity Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn total(items List[Item]) Int {
// expect-formatted: \tvar result = 0
// expect-formatted: \tfor item in items {
// expect-formatted: \t\tresult += item.price * item.quantity
// expect-formatted: \t}
// expect-formatted: \treturn result
// expect-formatted: }
