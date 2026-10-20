# conform: tags=parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:236 TestUniversalToStringCompletion
type Item:
    value: Int
fn text(value: Item) String:
    return value.|
