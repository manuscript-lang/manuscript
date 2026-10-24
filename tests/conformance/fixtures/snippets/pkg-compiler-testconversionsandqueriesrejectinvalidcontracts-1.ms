# conform: tags=diagnostics,optional,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:11 TestConversionsAndQueriesRejectInvalidContracts
def cause(value: Int) -> String: "cause"

def wrong(value: Optional[Int]) -> Result[Int, String]: value.ok_or_else(cause)
