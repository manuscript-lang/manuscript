# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:344 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
from "./helper.ms" import first, second

def answer() -> Int:
    return first()
