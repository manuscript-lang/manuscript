# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/review_test.go:54 TestReviewNamesErrorFlowAndContractChanges
export fn load(n: Int) Int!:
    return ok(n)
