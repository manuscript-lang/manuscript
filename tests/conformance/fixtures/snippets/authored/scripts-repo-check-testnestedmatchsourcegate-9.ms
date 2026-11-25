// conform: tags=diagnostics,formatter,match,strings,tier-core
// conform: phase=check,parse
// conform: origin=scripts/repo-check/nested_match_test.go:30 TestNestedMatchSourceGate
// match match
fn use() String => "match match"
// expect-exit: 0
