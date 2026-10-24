# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:26 TestNestedMatchLint
def use(value: Optional[Int]) -> Int:
    return match value:
        case some(_):
            match value:
                case some(_):
                    match value:
                        case some(n): n
                        case none: 0
                case none: 0
        case none: 0
