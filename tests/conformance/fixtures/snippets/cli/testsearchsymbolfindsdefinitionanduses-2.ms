// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=internal/cli/agent_test.go:59 TestSearchSymbolFindsDefinitionAndUses
import double from "./main.ms"

fn quad(v Int) Int {
	return double(double(v))
}
// expect-error: MS2002 4:1 cannot find module ./main.ms (looked for main.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
