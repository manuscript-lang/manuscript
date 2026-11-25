// conform: tags=closures,diagnostics,formatter,sets,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/core_parity_test.go:17 TestCoreParityRejectsInvalidContracts
fn wrong(value Set[Int]) Void {
	output := value.map(n => n.to_float())
}
// expect-error: MS3021 5:21 Float does not satisfy Hashable; Float has no Hashable implementation, so wrap it in a type with an Int or String key, or use Decimal
