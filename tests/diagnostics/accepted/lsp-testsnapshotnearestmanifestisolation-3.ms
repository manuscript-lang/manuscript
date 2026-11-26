// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:255 TestSnapshotNearestManifestIsolation
export fn value() Int => 2
// expect-exit: 0
