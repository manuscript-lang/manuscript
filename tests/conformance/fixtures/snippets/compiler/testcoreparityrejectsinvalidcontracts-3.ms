# conform: tags=closures,diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/core_parity_test.go:21 TestCoreParityRejectsInvalidContracts
fn wrong(value: Map[String, Int]) Unit:
    let output = value.filter(fn k, n: n)
