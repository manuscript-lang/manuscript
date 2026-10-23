# conform: tags=alternatives,faults,formatter,generics,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/core_parity_test.go:24 TestCoreParityRejectsInvalidContracts
type Result[T, E]:
    case ok(value: T)
    case error(cause: E)

fn wrong(value: Result[Int, String]) Int: value.get()
