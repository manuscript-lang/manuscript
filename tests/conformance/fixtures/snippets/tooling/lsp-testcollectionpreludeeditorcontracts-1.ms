// conform: tags=diagnostics,formatter,lists,maps,sets,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/completion_test.go:316 TestCollectionPreludeEditorContracts
fn use(values List[Int], var entries Map[String, Int], unique Set[Int]) Void {
	entries.add("a", 1)
}
// expect-exit: 0
