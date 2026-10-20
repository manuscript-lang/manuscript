# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:58 TestProjectRenameUpdatesImportsLabelsAndAssignments
import add from "./helper.ms"
fn result() Int:
    return add(value: 1)
