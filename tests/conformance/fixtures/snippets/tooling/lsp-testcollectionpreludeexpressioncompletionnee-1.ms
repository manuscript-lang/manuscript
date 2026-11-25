// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/completion_test.go:100 TestCollectionPreludeExpressionCompletionNeedsNoImport
fn work() Void { ... }
// expect-exit: 0
