# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:18 TestNestedMatchLint
fn use(value: Int?) Int:
    return match value:
        some(_):
            match value:
                some(n): n
                none: 0
        none: 0
