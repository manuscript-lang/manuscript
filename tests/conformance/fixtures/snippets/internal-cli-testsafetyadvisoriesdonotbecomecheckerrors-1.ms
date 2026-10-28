# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=internal/cli/advisory_lint_test.go:16 TestSafetyAdvisoriesDoNotBecomeCheckErrors
fn use(value: Optional[Int]) Unit:
    match value:
        some(_):
            match value:
                some(_): unit
                none: unit
        none: unit
