// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:330 TestSnapshotLibraryDiscoversTests
export fn other() Int => 2
// expect-exit: 0
