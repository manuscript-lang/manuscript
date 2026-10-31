# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:26 TestNestedMatchLint
fn use(value: Int?) Int:
    return match value:
        _value:
            match value:
                _value:
                    match value:
                        n: n
                        none: 0
                none: 0
        none: 0
