# conform: tags=control-flow,diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_match_lint_test.go:16 TestResultMatchLint
fn use(value: Result[Int, Error]) Int:
    if let n = value:
        return n

    return 0
