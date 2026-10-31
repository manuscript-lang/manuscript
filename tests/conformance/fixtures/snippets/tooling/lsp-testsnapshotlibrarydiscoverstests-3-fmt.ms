# conform: tags=formatter,modules,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:331 TestSnapshotLibraryDiscoversTests
import value from "../src/value.ms"

test "checks source":
    let invalid: Int = "wrong"
