// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-aliases
type C = List[C]
// expect-error: MS2002 4:1 type alias C refers to itself; an alias names another type, so break the cycle with a type or enum
