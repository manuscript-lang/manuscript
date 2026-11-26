// conform: tags=diagnostics,faults,formatter,optional,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/optionals.md:63
fn display_name(move name String?) String {
	return name or "Anonymous"
}
// expect-exit: 0
