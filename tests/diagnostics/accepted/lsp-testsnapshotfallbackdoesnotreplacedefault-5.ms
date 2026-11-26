// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:213 TestSnapshotFallbackDoesNotReplaceDefault
export fn alone() Int => 3
// expect-exit: 0
