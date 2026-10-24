# conform: tags=diagnostics,lists,maps,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:17 TestCollectionSupportPreludeEditorContracts
def entries(values: List[Int]) -> List[ListEntry[Int]]: values.entries()

def pairs(values: Map[String, Int]) -> List[MapEntry[String, Int]]: values.entries()

def cut(values: List[Int]) -> Result[List[Int], CollectionError]: values.slice(0, 1)
