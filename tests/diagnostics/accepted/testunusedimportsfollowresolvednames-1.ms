// conform: tags=diagnostics,formatter,modules,stdlib-json,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:28 TestUnusedImportsFollowResolvedNames
import parse from "@std/data/json.ms"

fn answer(parse Int) Int {
	return parse
}
// expect-exit: 0
