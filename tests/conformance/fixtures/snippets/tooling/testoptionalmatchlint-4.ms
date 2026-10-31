# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/optional_match_lint_test.go:17 TestOptionalMatchLint
fn use(value: Int!) Int:
    return match value:
        ok(n): n
        error(_): 0
