# conform: tags=formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=scripts/repo-check/main_test.go:43 TestStandardSyntaxGate
type Data:
    count: Int = 3

impl Data:
    fn read() Int:
