// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/boundaries_test.go:73 TestRenameChangesStopsBetweenFiles
fn other() Int => 2
// expect-exit: 0
