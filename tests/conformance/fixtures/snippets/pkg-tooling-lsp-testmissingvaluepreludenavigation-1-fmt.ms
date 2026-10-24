# conform: tags=formatter,lists,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:89 TestMissingValuePreludeNavigation
def first(values: List[Int]) -> Result[Int, MissingValue]: values.first().ok_or()
