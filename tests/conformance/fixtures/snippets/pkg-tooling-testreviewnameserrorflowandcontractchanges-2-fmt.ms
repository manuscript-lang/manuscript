# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/review_test.go:54 TestReviewNamesErrorFlowAndContractChanges
export def load(n: Int) -> Result[Int, Error]:
    return ok(n)
