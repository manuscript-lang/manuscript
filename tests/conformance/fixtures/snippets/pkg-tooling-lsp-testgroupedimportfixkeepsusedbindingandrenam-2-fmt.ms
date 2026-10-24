# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:345 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
export def first() -> Int:
    return 1

export def second() -> Int:
    return 2
