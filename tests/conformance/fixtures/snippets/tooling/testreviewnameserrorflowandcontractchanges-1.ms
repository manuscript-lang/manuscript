# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/tooling/review_test.go:53 TestReviewNamesErrorFlowAndContractChanges

export fn load(n: Int) Int!Error:
    return ok(n)
