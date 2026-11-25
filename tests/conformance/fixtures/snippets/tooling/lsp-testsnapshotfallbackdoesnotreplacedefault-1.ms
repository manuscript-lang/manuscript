// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/snapshot_test.go:209 TestSnapshotFallbackDoesNotReplaceDefault
import value from "./good.ms"

export fn main() Int => value()
// expect-error: MS2002 4:1 cannot find module ./good.ms (looked for good.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
