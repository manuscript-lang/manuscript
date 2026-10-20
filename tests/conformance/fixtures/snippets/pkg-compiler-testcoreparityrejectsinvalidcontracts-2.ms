# conform: tags=closures,diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/core_parity_test.go:19 TestCoreParityRejectsInvalidContracts
fn wrong[U](value: Set[Int], transform: fn(value: Int) U) Unit:
    let output = value.map(transform)
