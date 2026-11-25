// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/parser/hints_test.go:71 TestFromIsOnlyAKeywordInImports
import a from "./x.ms"

fn f(from Int) Int {
	to := from + 1
	return to
}
// expect-error: MS2002 4:1 cannot find module ./x.ms (looked for x.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
