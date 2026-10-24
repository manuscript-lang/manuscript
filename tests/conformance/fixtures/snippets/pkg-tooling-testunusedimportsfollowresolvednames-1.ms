# conform: tags=diagnostics,modules,stdlib-json,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:28 TestUnusedImportsFollowResolvedNames
from "@std/json.ms" import parse

def answer(parse: Int) -> Int:
    return parse
