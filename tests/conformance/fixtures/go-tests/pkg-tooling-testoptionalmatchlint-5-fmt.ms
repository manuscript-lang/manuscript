# conform: tags=alternatives,formatter,match,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:18 TestOptionalMatchLint
type Shape:
    case Dot
    case Line
fn use(value: Shape) Int:
    return match value:
        Dot: 0
        Line: 1
