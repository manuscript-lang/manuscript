# conform: tags=diagnostics,faults,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_match_lint_test.go:17 TestResultMatchLint
fn use(value: Int!) Int:
    return value.get(0)
