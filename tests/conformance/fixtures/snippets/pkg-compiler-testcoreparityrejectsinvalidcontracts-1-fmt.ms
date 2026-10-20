# conform: tags=closures,formatter,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/core_parity_test.go:17 TestCoreParityRejectsInvalidContracts
fn wrong(value: Set[Int]) Unit:
    let output = value.map(fn(n): n.to_float())
