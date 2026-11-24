// conform: tags=formatter,match,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/nested_match_lint_test.go:18 TestNestedMatchLint
fn use(value Int?) Int:
    return match value:
        _value:
            match value:
                n => n
                null => 0
        null => 0
