# conform: tags=aliasing,formatter,optional,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:17
let inferred = some(1)  # Optional[Int]
let explicit = Optional[String].none
# Rejected: no type determines the absent payload.
let unknown = none
# Rejected: bindings still require explicit wrapping.
let wrong: Optional[String] = "Ada"
