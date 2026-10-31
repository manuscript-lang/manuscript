# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:24 TestNestedMatchLint
fn use(value: Int?) Int:
    return match (
        match value:
            x: x
            none: 0
    ):
        x: x
        none: 0
