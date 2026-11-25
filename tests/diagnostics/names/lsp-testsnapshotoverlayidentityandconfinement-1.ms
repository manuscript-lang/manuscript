// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:280 TestSnapshotOverlayIdentityAndConfinement
import value from "./new.ms"

export fn main() Int => value()
// expect-error: MS2002 4:1 cannot find module ./new.ms (looked for new.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
