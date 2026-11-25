// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:653 TestTypeBoundaries
fn old[T MissingBound](value T) T {
	return value
}
// expect-error: MS2001 4:10 unknown type MissingBound; declare it with 'type MissingBound:' / 'enum MissingBound:' / 'interface MissingBound:', declare it as a type parameter, or import it
