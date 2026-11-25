// conform: tags=diagnostics,formatter,modules,records,stdlib-json,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:29 TestUnusedImportsFollowResolvedNames
import parse from "@std/data/json.ms"

type Item {
	parse Int
}

fn answer() Item {
	return Item(parse: 1)
}
// expect-exit: 0
