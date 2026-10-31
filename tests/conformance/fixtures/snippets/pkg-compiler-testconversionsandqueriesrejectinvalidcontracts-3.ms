# conform: tags=alternatives,diagnostics,generics,optional,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:21 TestConversionsAndQueriesRejectInvalidContracts
type Optional[T]:
    case T
    case none

fn wrong(value: Int?) Result[Int, String]: value.ok_or("missing")
