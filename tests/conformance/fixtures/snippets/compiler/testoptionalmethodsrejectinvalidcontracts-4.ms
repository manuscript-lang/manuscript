// conform: tags=alternatives,diagnostics,faults,generics,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
enum Optional[T]:
    T
    none

fn wrong(value: Int?) Int:
    return value.get()
