// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/snapshot_test.go:212 TestSnapshotFallbackDoesNotReplaceDefault
export fn bad() Int => "wrong"
// expect-error: MS3001 4:24 expected Int, found String (in the return value)
