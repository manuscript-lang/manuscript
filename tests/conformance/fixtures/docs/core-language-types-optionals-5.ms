// conform: tags=closures,diagnostics,faults,formatter,optional,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/optionals.md:70
fn display_name(create fn() String, move name String?) String {
	return name or create()
}
// expect-exit: 0
