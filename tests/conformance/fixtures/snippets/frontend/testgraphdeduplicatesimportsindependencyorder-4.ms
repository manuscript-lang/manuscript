// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/frontend/source_test.go:31 TestGraphDeduplicatesImportsInDependencyOrder
import (
	left from "./left.ms",
	right from "./right.ms",
)

fn result() Int => return left() + right()
// expect-error: MS2002 4:1 cannot find module ./left.ms (looked for left.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
