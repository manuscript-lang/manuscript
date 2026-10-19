# conform: tags=match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:122 TestImportedPatternNamesAndAliases
"
fn use() Int:
    match fail():
        error(NotFound): return 1
        ok(value): return value
fn record(value: Optional[Item]) Int:
    match value:
        some(Item): return Item.value
        none: return 0
