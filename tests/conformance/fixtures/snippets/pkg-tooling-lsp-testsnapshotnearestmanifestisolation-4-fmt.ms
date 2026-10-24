# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:256 TestSnapshotNearestManifestIsolation
from "@local/value.ms" import value

export def use() -> Int: value()
