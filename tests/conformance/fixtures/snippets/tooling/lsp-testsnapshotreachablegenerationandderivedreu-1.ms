// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:165 TestSnapshotReachableGenerationAndDerivedReuse
import value from "./dep.ms"

export fn main() Int => value()
// expect-error: MS2002 4:1 cannot find module ./dep.ms (looked for dep.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
