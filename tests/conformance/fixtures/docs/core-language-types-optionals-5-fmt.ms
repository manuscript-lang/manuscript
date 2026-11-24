// conform: tags=closures,faults,formatter,optional,parser,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/optionals.md:70
fn display_name(create fn() String, move name String?) String:
	return name or create()
