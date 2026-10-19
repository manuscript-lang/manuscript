# conform: tags=closures,formatter,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/core_parity_test.go:19 TestCoreParityRejectsInvalidContracts
fn wrong[U](value: Set[Int], transform: fn(value: Int) U) Unit:
    let output = value.map(transform)
