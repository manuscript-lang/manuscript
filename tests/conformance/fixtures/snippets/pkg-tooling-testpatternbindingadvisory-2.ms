# conform: tags=diagnostics,match,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:23 TestPatternBindingAdvisory
type Item:
    value: Int

fn use(value: Optional[Item]) Int:
    match value:
        some(Item): return Item.value
        none: return 0
