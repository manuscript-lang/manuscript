// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/frontend/source_test.go:30 TestGraphDeduplicatesImportsInDependencyOrder
import value from "./shared.ms"

export fn right() Int => return value()
// expect-error: MS2002 4:1 cannot find module ./shared.ms (looked for shared.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
