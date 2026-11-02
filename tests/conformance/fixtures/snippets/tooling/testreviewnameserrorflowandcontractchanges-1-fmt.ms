# conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/review_test.go:53 TestReviewNamesErrorFlowAndContractChanges

export fn load(n: Int) Int!Error:
    return ok(n)
