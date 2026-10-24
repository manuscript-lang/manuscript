# conform: tags=closures,diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/nested_match_lint_test.go:22 TestNestedMatchLint
def use(value: Optional[Int]) -> Int:
    return match value:
        case some(_):
            let callback = lambda (
                n: Int = match value:
                    case some(x): x
                    case none: 0
            ) -> Int:
                return n
            callback()
        case none: 0
