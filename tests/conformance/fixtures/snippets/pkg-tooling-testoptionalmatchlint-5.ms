# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/optional_match_lint_test.go:18 TestOptionalMatchLint
type Shape:
    case Dot
    case Line

def use(value: Shape) -> Int:
    return match value:
        case Dot: 0
        case Line: 1
