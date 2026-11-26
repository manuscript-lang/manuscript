// conform: tags=control-flow,formatter,optional,parser,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/optionals.md:95
fn display_name(name String?) String {
	value := name
	if value != null { return value }

	return "Anonymous"
}
// expect-format: unchanged
