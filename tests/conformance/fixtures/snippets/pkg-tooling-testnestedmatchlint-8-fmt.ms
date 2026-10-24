# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:28 TestNestedMatchLint
def inner(value: Optional[Int]) -> Int:
    return match value:
        case some(n): n
        case none: 0

def use(value: Optional[Int]) -> Int:
    return match value:
        case some(_): inner(value)
        case none: 0
