// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/local_extensions_test.go:34 TestLocalExtensionBoundaries
import invoke from "./domain.ms"

fn use(value Box[Int]) Int {
	return invoke(value)
}
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
