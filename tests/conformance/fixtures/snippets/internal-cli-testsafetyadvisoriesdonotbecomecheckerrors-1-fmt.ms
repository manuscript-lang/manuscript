# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/advisory_lint_test.go:16 TestSafetyAdvisoriesDoNotBecomeCheckErrors
def use(value: Optional[Int]) -> Unit:
    match value:
        case some(_):
            match value:
                case some(_): ()
                case none: ()
        case none: ()
