// conform: tags=closures,formatter,optional,parser,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/optionals.md:86
fn first_number(text String?) Int?:
	if text == null: return null
	return text.trim().parse_int()
