// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/bound_recovery_test.go:44 checkInvalidBounds
fn unknown[T Missing](value T) Void => return
// expect-error: MS2001 4:14 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
