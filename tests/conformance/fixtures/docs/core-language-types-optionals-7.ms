// conform: tags=closures,diagnostics,optional,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/optionals.md:86
fn first_number(text String?) Int?:
	if text == null: return null
	return text.trim().parse_int()
