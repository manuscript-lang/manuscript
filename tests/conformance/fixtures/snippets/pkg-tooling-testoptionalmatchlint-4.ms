# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/optional_match_lint_test.go:17 TestOptionalMatchLint
def use(value: Result[Int, Error]) -> Int:
    return match value:
        case ok(n): n
        case error(_): 0
