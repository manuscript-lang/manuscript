# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:160 TestCodeActionFilteringAndUnusedImportFix
from "@std/collections.ms" import ListBuilder

def answer() -> Int:
    return 42
