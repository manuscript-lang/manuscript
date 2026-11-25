// conform: tags=closures,diagnostics,formatter,optional,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/optionals.md:86
fn first_number(text String?) Int? {
	if text == null { return null }
	return text.trim().parse_int()
}
// expect-exit: 0
