# conform: tags=formatter,modules,parser,stdlib-json,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:28 TestUnusedImportsFollowResolvedNames
from "@std/json.ms" import parse

def answer(parse: Int) -> Int:
    return parse
