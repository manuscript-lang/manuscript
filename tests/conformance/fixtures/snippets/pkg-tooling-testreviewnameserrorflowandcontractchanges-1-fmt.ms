# conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/review_test.go:53 TestReviewNamesErrorFlowAndContractChanges
from "@std/core.ms" import TextError

export def load(n: Int) -> Result[Int, TextError]:
    return ok(n)
