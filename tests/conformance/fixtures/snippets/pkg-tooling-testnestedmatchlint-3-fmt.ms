# conform: tags=closures,formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:20 TestNestedMatchLint
fn use(value: Int?) Int:
    return match value:
        some(_):
            let callback = fn() Int:
                return match value:
                    some(n): n
                    none: 0
            callback()
        none: 0
