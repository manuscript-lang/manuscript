# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=internal/cli/advisory_lint_test.go:18 TestSafetyAdvisoriesDoNotBecomeCheckErrors

fn fail() Int!Error:
    return error(Error("boom"))

fn use() Unit:
    let _ = fail()
