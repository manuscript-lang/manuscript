// conform: tags=diagnostics,generics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/bound_recovery_test.go:43 checkInvalidBounds
type Data {
	value Int
}

fn record[T Data](value T) Void => return
// expect-error: MS3000 8:13 a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'
