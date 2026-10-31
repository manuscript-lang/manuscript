# conform: tags=aliasing,diagnostics,optional,records,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:17
let inferred = 1  # Int?
let explicit: String? = none
# Rejected: no type determines the absent payload.
let unknown = none
# Rejected: bindings still require explicit wrapping.
let wrong: String? = "Ada"
