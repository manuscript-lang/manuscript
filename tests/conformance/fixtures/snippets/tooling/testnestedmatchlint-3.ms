# conform: tags=closures,diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:20 TestNestedMatchLint
fn use(value: Int?) Int:
    return match value:
        _value:
            let callback = fn() Int:
                return match value:
                    n: n
                    none: 0
            callback()
        none: 0
