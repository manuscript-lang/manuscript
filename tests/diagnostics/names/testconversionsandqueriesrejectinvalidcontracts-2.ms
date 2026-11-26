// conform: tags=diagnostics,formatter,maps,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/conversions_queries_test.go:19 TestConversionsAndQueriesRejectInvalidContracts
fn check(value Int, key String) Bool => true

fn wrong(value Map[String, Int]) Bool => value.every(check)
// expect-error: MS2001 6:48 unknown or ambiguous member every on Map[String, Int]; every(predicate) is now all(predicate)
