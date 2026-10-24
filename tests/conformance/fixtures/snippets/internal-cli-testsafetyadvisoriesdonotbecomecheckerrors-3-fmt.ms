# conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=internal/cli/advisory_lint_test.go:18 TestSafetyAdvisoriesDoNotBecomeCheckErrors
from "@std/core.ms" import TextError

def fail() -> Result[Int, TextError]:
    return error(TextError("boom"))

def use() -> Unit:
    fail()
