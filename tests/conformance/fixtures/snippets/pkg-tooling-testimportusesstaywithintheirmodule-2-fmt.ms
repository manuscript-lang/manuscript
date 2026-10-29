# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:51 TestImportUsesStayWithinTheirModule
import value from "./value.ms"

export fn helper() Int:
    return 2
