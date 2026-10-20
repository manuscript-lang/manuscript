# conform: tags=formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/conversions_queries_test.go:19 TestConversionsAndQueriesRejectInvalidContracts
fn check(value: Int, key: String) Bool: true
fn wrong(value: Map[String, Int]) Bool: value.every(check)
