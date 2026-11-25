// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/bound_recovery_test.go:41 checkInvalidBounds
fn mutual[T U, U T](value T) Void => return
// expect-error: MS3000 4:13 a bound must be an interface, but U resolves to a type parameter; rename the type parameter or name an interface
// expect-error: MS3000 4:18 a bound must be an interface, but T resolves to a type parameter; rename the type parameter or name an interface
