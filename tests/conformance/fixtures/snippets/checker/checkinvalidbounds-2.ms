// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/bound_recovery_test.go:40 checkInvalidBounds
fn recursive[T T](value T) Void => return
// expect-error: MS3000 4:16 a bound must be an interface, but T resolves to a type parameter; rename the type parameter or name an interface
