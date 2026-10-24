# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:25 TestPatternBindingAdvisory
def use(value: Optional[Int]) -> Int:
    match value:
        case some(Int): return Int
        case none: return 0
