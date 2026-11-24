// conform: tags=formatter,match,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/nested_match_lint_test.go:28 TestNestedMatchLint
fn inner(value: Int?) Int:
    return match value:
        n: n
        null: 0

fn use(value: Int?) Int:
    return match value:
        _value: inner(value)
        null: 0
