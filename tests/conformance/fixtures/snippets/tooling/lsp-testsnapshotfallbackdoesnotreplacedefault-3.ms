// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:211 TestSnapshotFallbackDoesNotReplaceDefault
import bad from "./bad.ms"

export fn other() Int => bad()
// expect-error: MS2002 4:1 cannot find module ./bad.ms (looked for bad.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
