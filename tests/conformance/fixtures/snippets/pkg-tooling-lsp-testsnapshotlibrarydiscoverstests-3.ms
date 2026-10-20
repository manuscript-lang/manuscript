# conform: tags=diagnostics,modules,testing,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:331 TestSnapshotLibraryDiscoversTests
import value from "../src/value.ms"
test "checks source":
    let invalid: Int = "wrong"
