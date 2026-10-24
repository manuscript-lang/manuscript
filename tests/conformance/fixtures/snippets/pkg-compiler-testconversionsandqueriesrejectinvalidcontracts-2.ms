# conform: tags=diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:19 TestConversionsAndQueriesRejectInvalidContracts
def check(value: Int, key: String) -> Bool: True

def wrong(value: Map[String, Int]) -> Bool: value.every(check)
