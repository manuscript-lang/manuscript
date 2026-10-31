# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:27 TestNestedMatchLint
fn use(value: Int?) Int:
    let present = match value:
        n: n
        none: return 0

    return match value:
        n: present + n
        none: 0
