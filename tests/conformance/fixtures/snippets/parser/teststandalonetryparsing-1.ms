// conform: tags=diagnostics,formatter,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/parser/standalone_try_test.go:7 TestStandaloneTryParsing
fn f() Void!String { ... }
// expect-exit: 0
