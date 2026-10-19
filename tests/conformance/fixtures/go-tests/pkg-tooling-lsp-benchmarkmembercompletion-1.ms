# conform: tags=lists,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:248 BenchmarkMemberCompletion
fn answer(items: List[String]) Int:
    return items.
