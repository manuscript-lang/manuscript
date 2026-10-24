# conform: tags=diagnostics,lists,maps,sets,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/completion_test.go:316 TestCollectionPreludeEditorContracts
def use(values: List[Int], var entries: Map[String, Int], unique: Set[Int]) -> Unit:
    entries.add("a", 1)
