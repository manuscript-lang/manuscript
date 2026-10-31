# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_match_lint_test.go:15 TestResultMatchLint
fn use(value: Int!) Int:
    match value:
        ok(n): return n
        error(_): return 0
