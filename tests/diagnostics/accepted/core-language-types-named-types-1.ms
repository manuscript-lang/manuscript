// conform: tags=diagnostics,formatter,optional,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/named-types.md:10
type Customer {
	name String
	email String?
}
// expect-exit: 0
