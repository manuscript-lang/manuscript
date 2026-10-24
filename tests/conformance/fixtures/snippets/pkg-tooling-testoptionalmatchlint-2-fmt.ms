# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:15 TestOptionalMatchLint
def use(value: Optional[Int]) -> Int:
    return match value:
        case some(n): n
        case none: 0
