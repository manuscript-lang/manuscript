# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:211 TestSnapshotFallbackDoesNotReplaceDefault
from "./bad.ms" import bad

export def other() -> Int: bad()
