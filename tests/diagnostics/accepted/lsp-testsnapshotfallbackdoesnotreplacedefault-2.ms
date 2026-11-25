// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:210 TestSnapshotFallbackDoesNotReplaceDefault
export fn value() Int => 1
// expect-exit: 0
