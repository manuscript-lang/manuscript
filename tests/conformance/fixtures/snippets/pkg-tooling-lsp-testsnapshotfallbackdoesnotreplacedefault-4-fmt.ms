# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:212 TestSnapshotFallbackDoesNotReplaceDefault
export def bad() -> Int: "wrong"
