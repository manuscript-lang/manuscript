# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:212 TestSnapshotFallbackDoesNotReplaceDefault
export def bad() -> Int: "wrong"
