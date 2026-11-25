// conform: tags=alternatives,diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/alternatives.md:10
enum Payment {
	Paid(receipt String)
	Declined(reason String)
	Pending(reference String)
}
// expect-exit: 0
