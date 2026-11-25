// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/bound_recovery_test.go:42 checkInvalidBounds
fn primitive[T Int](value T) Void => return
// expect-error: MS3000 4:16 a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'
