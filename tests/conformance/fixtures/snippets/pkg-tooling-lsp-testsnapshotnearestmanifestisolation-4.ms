# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:256 TestSnapshotNearestManifestIsolation
from "@local/value.ms" import value

export def use() -> Int: value()
