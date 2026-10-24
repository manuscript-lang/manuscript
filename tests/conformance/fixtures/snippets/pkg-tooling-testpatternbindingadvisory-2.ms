# conform: tags=diagnostics,match,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:23 TestPatternBindingAdvisory
type Item:
    value: Int

def use(value: Optional[Item]) -> Int:
    match value:
        case some(Item): return Item.value
        case none: return 0
