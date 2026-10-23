# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/tooling/review_test.go:53 TestReviewNamesErrorFlowAndContractChanges
import {TextError} from "@std/core.ms"

export fn load(n: Int) Result[Int, TextError]:
    return ok(n)
