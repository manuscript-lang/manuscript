# conform: tags=formatter,lists,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:203 TestStandardLibraryNavigationUsesCompilerSources
fn count(values: List[String]) Int:
    return values.length()
