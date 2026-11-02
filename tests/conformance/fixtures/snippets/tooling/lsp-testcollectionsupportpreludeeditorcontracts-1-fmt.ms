# conform: tags=formatter,lists,maps,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:17 TestCollectionSupportPreludeEditorContracts
fn entries(values: List[Int]) List[ListEntry[Int]]: values.entries()

fn pairs(values: Map[String, Int]) List[MapEntry[String, Int]]: values.entries()

fn cut(values: List[Int]) List[Int]!CollectionError: values.slice(0, 1)
