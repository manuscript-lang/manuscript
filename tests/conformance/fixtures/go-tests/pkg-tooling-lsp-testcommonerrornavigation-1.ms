# conform: tags=diagnostics,match,modules,stdlib-json,strings,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/navigation_test.go:120 TestCommonErrorNavigation
import JsonError from "@std/json.ms"
fn describe(cause: Error) String:
    match cause:
        JsonError(json):
            return json.message()
        _:
            return cause.message()
