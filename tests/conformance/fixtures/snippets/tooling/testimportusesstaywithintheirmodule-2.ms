# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:51 TestImportUsesStayWithinTheirModule
import value from "./value.ms"

export fn helper() Int:
    return 2
