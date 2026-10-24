# conform: tags=alternatives,diagnostics,faults,generics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
type Optional[T]:
    case some(value: T)
    case none

def wrong(value: Optional[Int]) -> Int:
    return value.get()
