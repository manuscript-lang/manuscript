# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:58 TestProjectRenameUpdatesImportsLabelsAndAssignments
import add from "./helper.ms"

fn result() Int:
    return add(value: 1)
