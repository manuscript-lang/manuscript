# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:24 TestNestedMatchLint
fn use(value: Int?) Int:
    return match (
        match value:
            some(x): some(x)
            none: some(0)
    ):
        some(x): x
        none: 0
