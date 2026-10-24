# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_match_lint_test.go:15 TestResultMatchLint
def use(value: Result[Int, Error]) -> Int:
    match value:
        case ok(n): return n
        case error(_): return 0
