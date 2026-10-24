# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:13 TestResultTypeFollowsParametersWithoutArrow
interface Read:
    def read() -> Int
