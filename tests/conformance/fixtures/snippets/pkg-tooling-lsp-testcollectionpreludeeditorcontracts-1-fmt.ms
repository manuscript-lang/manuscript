# conform: tags=formatter,lists,maps,parser,sets,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:316 TestCollectionPreludeEditorContracts
fn use(values: List[Int], var entries: Map[String, Int], unique: Set[Int]) Unit:
    entries.add("a", 1)
