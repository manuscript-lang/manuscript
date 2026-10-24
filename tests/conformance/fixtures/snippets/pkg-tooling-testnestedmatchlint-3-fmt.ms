# conform: tags=closures,formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/nested_match_lint_test.go:20 TestNestedMatchLint
def use(value: Optional[Int]) -> Int:
    return match value:
        case some(_):
            let callback = lambda () -> Int:
                return match value:
                    case some(n): n
                    case none: 0
            callback()
        case none: 0
