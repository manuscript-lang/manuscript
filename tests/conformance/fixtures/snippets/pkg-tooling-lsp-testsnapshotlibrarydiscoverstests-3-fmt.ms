# conform: tags=formatter,modules,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:331 TestSnapshotLibraryDiscoversTests
from "../src/value.ms" import value

test "checks source":
    let invalid: Int = "wrong"
