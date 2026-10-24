# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:14 TestOptionalMatchLint
def use(value: Optional[Int]) -> Int:
    match value:
        case some(n): return n
        case none: return 0
