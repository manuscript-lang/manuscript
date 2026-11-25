// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:240 TestSnapshotNilProgramPreservesDefaultFailure
export fn other() Int => 1
// expect-exit: 0
