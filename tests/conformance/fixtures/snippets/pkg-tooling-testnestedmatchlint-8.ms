# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:28 TestNestedMatchLint
fn inner(value: Optional[Int]) Int:
    return match value:
        some(n): n
        none: 0

fn use(value: Optional[Int]) Int:
    return match value:
        some(_): inner(value)
        none: 0
