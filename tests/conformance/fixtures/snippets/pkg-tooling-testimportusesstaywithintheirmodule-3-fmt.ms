# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:52 TestImportUsesStayWithinTheirModule
from "./value.ms" import value
from "./helper.ms" import helper

def answer() -> Int:
    return value() + helper()
