# conform: tags=alternatives,diagnostics,generics,optional,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:25 TestConversionsAndQueriesRejectInvalidContracts
type Result[T, E]:
    case ok(value: T)
    case error(cause: E)

fn wrong(value: Result[Int, String]) Int?: value.to_optional()
