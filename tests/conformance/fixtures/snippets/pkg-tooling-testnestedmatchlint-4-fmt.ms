# conform: tags=closures,formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:22 TestNestedMatchLint
fn use(value: Optional[Int]) Int:
    return match value:
        some(_):
            let callback = fn(n: Int = match value:
                some(x): x
                none: 0
            ) Int:
                return n
            callback()
        none: 0
