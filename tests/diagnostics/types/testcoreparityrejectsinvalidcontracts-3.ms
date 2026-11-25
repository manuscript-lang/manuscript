// conform: tags=closures,diagnostics,formatter,maps,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/core_parity_test.go:21 TestCoreParityRejectsInvalidContracts
fn wrong(value Map[String, Int]) Void {
	output := value.filter((k, n) => n)
}
// expect-error: MS3001 5:38 expected Bool, found Int (in the return value)
