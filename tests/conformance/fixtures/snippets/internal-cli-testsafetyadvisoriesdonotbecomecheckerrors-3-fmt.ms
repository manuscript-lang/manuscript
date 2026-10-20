# conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=internal/cli/advisory_lint_test.go:18 TestSafetyAdvisoriesDoNotBecomeCheckErrors
import {TextError} from "@std/errors.ms"
fn fail() Result[Int, TextError]:
    return error(TextError("boom"))
fn use() Unit:
    fail()
