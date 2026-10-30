# conform: tags=formatter,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:23 TestPatternBindingAdvisory
type Item:
    value: Int

fn use(value: Item?) Int:
    match value:
        some(Item): return Item.value
        none: return 0
