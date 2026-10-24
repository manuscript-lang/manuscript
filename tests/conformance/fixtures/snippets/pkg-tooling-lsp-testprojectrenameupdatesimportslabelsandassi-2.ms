# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:58 TestProjectRenameUpdatesImportsLabelsAndAssignments
from "./helper.ms" import add

def result() -> Int:
    return add(value: 1)
