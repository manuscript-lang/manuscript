// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:18 TestEmptyFunctionDeclarations
fn empty() Void { ... }

// empty body
fn answer() Int => return 3
// expect-exit: 0
