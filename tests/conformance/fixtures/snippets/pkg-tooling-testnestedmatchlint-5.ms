# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:24 TestNestedMatchLint
def use(value: Optional[Int]) -> Int:
    return match (
        match value:
            case some(x): some(x)
            case none: some(0)
    ):
        case some(x): x
        case none: 0
