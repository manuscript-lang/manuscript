# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:25 TestPatternBindingAdvisory
def use(value: Optional[Int]) -> Int:
    match value:
        case some(Int): return Int
        case none: return 0
