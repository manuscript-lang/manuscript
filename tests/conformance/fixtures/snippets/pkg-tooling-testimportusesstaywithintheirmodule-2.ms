# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:51 TestImportUsesStayWithinTheirModule
from "./value.ms" import value

export def helper() -> Int:
    return 2
