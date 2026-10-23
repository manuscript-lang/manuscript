# conform: tags=closures,diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:22 TestNestedMatchLint
fn use(value: Optional[Int]) Int:
    return match value:
        some(_):
            let callback = fn(
                n: Int = match value:
                    some(x): x
                    none: 0
            ) Int:
                return n
            callback()
        none: 0
