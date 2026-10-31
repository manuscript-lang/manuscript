# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:57 TestProjectRenameUpdatesImportsLabelsAndAssignments
export fn add(value: Int) Int:
    var current = value
    current = current + 1
    return current
