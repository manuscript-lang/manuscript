// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/lambda_keyword_test.go:40 TestUnitBindingKeywordDiagnostic
fn before() Void => void

fn broken() Void { ... }
// expect-exit: 0
