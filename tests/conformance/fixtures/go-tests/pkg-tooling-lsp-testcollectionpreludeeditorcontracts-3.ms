# conform: tags=maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:334 TestCollectionPreludeEditorContracts
fn use(entries: Map[String, Int]) Unit:
    entries.add(key: "a", value: |
