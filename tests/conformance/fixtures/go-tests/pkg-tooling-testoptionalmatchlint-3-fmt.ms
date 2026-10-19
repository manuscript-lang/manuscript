# conform: tags=control-flow,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:16 TestOptionalMatchLint
fn use(value: Optional[Int]) Int:
    if let n = value:
        return n
    return 0
