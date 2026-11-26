// conform: tags=diagnostics,formatter,match,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/nested_match_lint_test.go:29 TestNestedMatchLint
fn use() String => "match nested match"
// expect-exit: 0
