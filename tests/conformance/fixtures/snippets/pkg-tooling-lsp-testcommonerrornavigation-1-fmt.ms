# conform: tags=formatter,match,modules,parser,stdlib-json,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:120 TestCommonErrorNavigation
from "@std/json.ms" import JsonError

def describe(cause: Error) -> String:
    match cause:
        case JsonError(json):
            return json.message()
        case _:
            return cause.message()
