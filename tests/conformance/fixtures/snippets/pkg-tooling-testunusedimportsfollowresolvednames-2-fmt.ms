# conform: tags=formatter,modules,parser,records,stdlib-json,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:29 TestUnusedImportsFollowResolvedNames
import parse from "@std/json.ms"

type Item:
    parse: Int

fn answer() Item:
    return Item(parse: 1)
