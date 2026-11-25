// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/boundaries_test.go:56 TestRenameChangesStopsBetweenFiles
fn first() Int => 1
// expect-exit: 0
