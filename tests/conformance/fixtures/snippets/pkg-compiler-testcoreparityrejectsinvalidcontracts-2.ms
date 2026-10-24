# conform: tags=closures,diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/core_parity_test.go:19 TestCoreParityRejectsInvalidContracts
def wrong[U](value: Set[Int], transform: Callable[[Int], U]) -> Unit:
    let output = value.map(transform)
