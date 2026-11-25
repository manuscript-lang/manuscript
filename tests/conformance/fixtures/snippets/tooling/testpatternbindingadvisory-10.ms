// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/pattern_lint_test.go:40 TestPatternBindingAdvisory
fn NotFound() Int => 2
// expect-exit: 0
