// conform: tags=alternatives,diagnostics,formatter,generics,optional,records,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/conversions_queries_test.go:21 TestConversionsAndQueriesRejectInvalidContracts
enum Optional[T] {
	T
	null
}

fn wrong(value Int?) Int!String => ok_or(value, "missing")
// expect-error: MS2001 4:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
