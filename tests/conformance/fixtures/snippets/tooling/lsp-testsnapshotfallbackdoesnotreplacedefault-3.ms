# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:211 TestSnapshotFallbackDoesNotReplaceDefault
import bad from "./bad.ms"

export fn other() Int: bad()
