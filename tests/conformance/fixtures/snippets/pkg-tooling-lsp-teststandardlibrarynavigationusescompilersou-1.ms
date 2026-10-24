# conform: tags=diagnostics,lists,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:203 TestStandardLibraryNavigationUsesCompilerSources
def count(values: List[String]) -> Int:
    return values.length()
