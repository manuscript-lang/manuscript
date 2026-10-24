# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:211 TestSnapshotFallbackDoesNotReplaceDefault
from "./bad.ms" import bad

export def other() -> Int: bad()
