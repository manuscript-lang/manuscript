# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:14 TestOptionalMatchLint
fn use(value: Optional[Int]) Int:
    match value:
        some(n): return n
        none: return 0
