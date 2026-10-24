# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:345 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
export def first() -> Int:
    return 1

export def second() -> Int:
    return 2
