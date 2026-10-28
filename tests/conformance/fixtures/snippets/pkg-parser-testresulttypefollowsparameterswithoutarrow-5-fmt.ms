# conform: tags=formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:14 TestResultTypeFollowsParametersWithoutArrow
type Box:
    value: Int

impl Box:
    fn get() Int: self.value
