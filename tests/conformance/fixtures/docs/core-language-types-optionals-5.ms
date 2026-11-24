// conform: tags=closures,diagnostics,faults,optional,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/optionals.md:70
fn display_name(create: fn() String, move name: String?) String:
	return name or create()
