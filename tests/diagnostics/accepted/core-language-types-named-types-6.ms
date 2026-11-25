// conform: tags=diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/named-types.md:74
type CustomerId {
	value String
}

type OrderId {
	value String
}
// expect-exit: 0
