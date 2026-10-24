# conform: tags=closures,diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/core_parity_test.go:17 TestCoreParityRejectsInvalidContracts
def wrong(value: Set[Int]) -> Unit:
    let output = value.map(lambda n: n.to_float())
