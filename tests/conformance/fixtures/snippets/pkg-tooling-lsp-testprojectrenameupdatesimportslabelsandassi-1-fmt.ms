# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:57 TestProjectRenameUpdatesImportsLabelsAndAssignments
export def add(value: Int) -> Int:
    var current = value
    current = current + 1
    return current
