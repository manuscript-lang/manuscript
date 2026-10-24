# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:27 TestNestedMatchLint
def use(value: Optional[Int]) -> Int:
    let present = match value:
        case some(n): n
        case none: return 0

    return match value:
        case some(n): present + n
        case none: 0
