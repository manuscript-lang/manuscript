// conform: tags=aliasing,formatter,optional,parser,records,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/optionals.md:17
inferred := 1  // Int?
explicit: String? := none
// Rejected: no type determines the absent payload.
unknown := none
// Rejected: bindings still require explicit wrapping.
wrong: String? := "Ada"
