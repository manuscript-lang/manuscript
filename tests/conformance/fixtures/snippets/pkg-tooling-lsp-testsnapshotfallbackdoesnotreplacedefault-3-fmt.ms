# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:211 TestSnapshotFallbackDoesNotReplaceDefault
import bad from "./bad.ms"
export fn other() Int: bad()
