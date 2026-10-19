# conform: tags=closures,formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/core_parity_test.go:21 TestCoreParityRejectsInvalidContracts
fn wrong(value: Map[String, Int]) Unit:
    let output = value.filter(fn(k, n): n)
