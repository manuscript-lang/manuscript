# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:26 TestNestedMatchLint
fn use(value: Optional[Int]) Int:
    return match value:
        some(_):
            match value:
                some(_):
                    match value:
                        some(n): n
                        none: 0
                none: 0
        none: 0
