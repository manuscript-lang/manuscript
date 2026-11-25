// conform: tags=closures,diagnostics,sets,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/core_parity_test.go:19 TestCoreParityRejectsInvalidContracts
fn wrong[U](value Set[Int], transform fn(Int) U) Void {
	output := value.map(transform)
}
// expect-error: MS3021 5:21 U does not satisfy Hashable; pass a type that already implements it
