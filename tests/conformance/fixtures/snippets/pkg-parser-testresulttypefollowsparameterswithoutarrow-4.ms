# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/parser/result_type_test.go:13 TestResultTypeFollowsParametersWithoutArrow
interface Read:
    def read() -> Int
