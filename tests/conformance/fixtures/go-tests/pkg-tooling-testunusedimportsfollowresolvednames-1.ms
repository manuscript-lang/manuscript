# conform: tags=diagnostics,modules,stdlib-json,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:28 TestUnusedImportsFollowResolvedNames
import parse from "@std/json.ms"
fn answer(parse: Int) Int:
    return parse
