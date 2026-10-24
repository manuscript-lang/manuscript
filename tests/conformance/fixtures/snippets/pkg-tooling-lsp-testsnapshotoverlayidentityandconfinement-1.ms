# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:280 TestSnapshotOverlayIdentityAndConfinement
from "./new.ms" import value

export def main() -> Int: value()
