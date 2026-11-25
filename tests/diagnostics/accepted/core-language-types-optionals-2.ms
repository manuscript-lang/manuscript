// conform: tags=aliasing,diagnostics,formatter,optional,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/optionals.md:17
inferred := 1  // Int?
explicit String? := null
// Rejected: no type determines the absent payload.
unknown := null
// Rejected: bindings still require explicit wrapping.
wrong String? := "Ada"
