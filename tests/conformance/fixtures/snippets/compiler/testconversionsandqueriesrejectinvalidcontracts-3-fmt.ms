// conform: tags=alternatives,formatter,generics,optional,parser,records,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/conversions_queries_test.go:21 TestConversionsAndQueriesRejectInvalidContracts
enum Optional[T]:
	T
	null

fn wrong(value: Int?) Int!String: ok_or(value, "missing")
