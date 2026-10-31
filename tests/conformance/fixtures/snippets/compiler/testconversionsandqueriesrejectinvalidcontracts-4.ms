# conform: tags=alternatives,diagnostics,generics,optional,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:25 TestConversionsAndQueriesRejectInvalidContracts
type T!E:
    case ok(value: T)
    case error(cause: E)

fn wrong(value: Int!String) Int?: value.to_optional()
