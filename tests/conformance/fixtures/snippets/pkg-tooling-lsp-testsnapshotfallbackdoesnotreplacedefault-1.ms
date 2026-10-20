# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:209 TestSnapshotFallbackDoesNotReplaceDefault
import value from "./good.ms"
export fn main() Int: value()
