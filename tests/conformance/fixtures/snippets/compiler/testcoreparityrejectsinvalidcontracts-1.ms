// conform: tags=closures,diagnostics,sets,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/core_parity_test.go:17 TestCoreParityRejectsInvalidContracts
fn wrong(value: Set[Int]) Unit:
    output := value.map(fn n: n.to_float())
