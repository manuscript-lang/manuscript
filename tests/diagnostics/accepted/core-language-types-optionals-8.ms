// conform: tags=control-flow,diagnostics,optional,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/optionals.md:95
fn display_name(name String?) String {
	value := name
	if value != null { return value.clone() }

	return "Anonymous"
}
// expect-exit: 0
