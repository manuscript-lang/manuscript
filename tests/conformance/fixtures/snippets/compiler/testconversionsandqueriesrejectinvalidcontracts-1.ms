// conform: tags=diagnostics,formatter,optional,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/conversions_queries_test.go:11 TestConversionsAndQueriesRejectInvalidContracts
fn cause(value Int) String => "cause"

fn wrong(value Int?) Int!String => value.ok_or_else(cause)
// expect-error: MS3000 6:42 a nullable has no method `ok_or_else`; write `if x != null { ... }` and use `x`
