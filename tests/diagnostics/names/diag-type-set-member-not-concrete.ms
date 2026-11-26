// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-sets
type Bad = Int | T
// expect-error: MS2001 4:18 unknown type T; declare it with 'type T:' / 'enum T:' / 'interface T:', declare it as a type parameter, or import it
