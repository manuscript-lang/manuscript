# conform: tags=alternatives,faults,formatter,generics,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
type Optional[T]:
    case T
    case none

fn wrong(value: Int?) Int:
    return value.get()
