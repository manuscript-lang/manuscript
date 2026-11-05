// conform: tags=alternatives,faults,formatter,generics,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
enum Optional[T]:
    T
    none

fn wrong(value: Int?) Int:
    return value.get()
