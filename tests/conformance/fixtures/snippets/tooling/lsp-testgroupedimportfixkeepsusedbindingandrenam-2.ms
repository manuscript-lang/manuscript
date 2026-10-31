# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:345 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
export fn first() Int:
    return 1

export fn second() Int:
    return 2
