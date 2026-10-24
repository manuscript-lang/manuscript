# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:51 TestImportUsesStayWithinTheirModule
from "./value.ms" import value

export def helper() -> Int:
    return 2
