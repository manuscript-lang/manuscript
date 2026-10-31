# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:24 TestNestedMatchLint
fn use(value: Int?) Int:
    return match (
        match value:
            x: x
            none: 0
    ):
        x: x
        none: 0
