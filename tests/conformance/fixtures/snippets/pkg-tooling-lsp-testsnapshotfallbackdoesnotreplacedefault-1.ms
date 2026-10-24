# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:209 TestSnapshotFallbackDoesNotReplaceDefault
from "./good.ms" import value

export def main() -> Int: value()
