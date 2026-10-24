# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:160 TestCodeActionFilteringAndUnusedImportFix
from "@std/collections.ms" import ListBuilder

def answer() -> Int:
    return 42
