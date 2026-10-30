# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:15 TestOptionalMatchLint
fn use(value: Int?) Int:
    return match value:
        some(n): n
        none: 0
