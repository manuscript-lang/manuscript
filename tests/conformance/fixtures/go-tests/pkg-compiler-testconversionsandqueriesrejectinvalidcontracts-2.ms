# conform: tags=diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:19 TestConversionsAndQueriesRejectInvalidContracts
fn check(value: Int, key: String) Bool: true
fn wrong(value: Map[String, Int]) Bool: value.every(check)
