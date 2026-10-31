# conform: tags=closures,diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:22 TestNestedMatchLint
fn use(value: Int?) Int:
    return match value:
        _value:
            let callback = fn(
                n: Int = match value:
                    x: x
                    none: 0
            ) Int:
                return n
            callback()
        none: 0
