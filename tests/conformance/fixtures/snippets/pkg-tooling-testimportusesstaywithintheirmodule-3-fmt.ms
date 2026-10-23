# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:52 TestImportUsesStayWithinTheirModule
import value from "./value.ms"
import helper from "./helper.ms"

fn answer() Int:
    return value() + helper()
