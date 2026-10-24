# conform: tags=formatter,modules,parser,records,stdlib-json,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:29 TestUnusedImportsFollowResolvedNames
from "@std/json.ms" import parse

type Item:
    parse: Int

def answer() -> Item:
    return Item(parse: 1)
