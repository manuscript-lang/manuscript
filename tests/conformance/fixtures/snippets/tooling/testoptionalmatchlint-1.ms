# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/optional_match_lint_test.go:14 TestOptionalMatchLint
fn use(value: Int?) Int:
    match value:
        n: return n
        none: return 0
