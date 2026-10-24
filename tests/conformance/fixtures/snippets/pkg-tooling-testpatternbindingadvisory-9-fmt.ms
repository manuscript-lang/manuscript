# conform: tags=alternatives,formatter,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:31 TestPatternBindingAdvisory
type Flag:
    case Ready

def use(value: Optional[Int]) -> Int:
    let Flag = 2

    match value:
        case some(Ready): return Ready
        case none: return 0
