# conform: tags=formatter,modules,parser,stdlib-json,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:28 TestUnusedImportsFollowResolvedNames
import parse from "@std/json.ms"
fn answer(parse: Int) Int:
    return parse
