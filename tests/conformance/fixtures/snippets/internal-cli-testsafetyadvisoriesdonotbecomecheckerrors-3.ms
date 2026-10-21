# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=internal/cli/advisory_lint_test.go:18 TestSafetyAdvisoriesDoNotBecomeCheckErrors
import {TextError} from "@std/core.ms"
fn fail() Result[Int, TextError]:
    return error(TextError("boom"))
fn use() Unit:
    fail()
