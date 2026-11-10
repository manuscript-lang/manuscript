// conform: tags=control-flow,diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/optional_match_lint_test.go:16 TestOptionalMatchLint
fn use(value: Int?) Int:
    if n := value:
        return n

    return 0
