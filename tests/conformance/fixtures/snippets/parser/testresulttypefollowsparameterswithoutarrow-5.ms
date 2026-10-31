# conform: tags=diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/result_type_test.go:14 TestResultTypeFollowsParametersWithoutArrow
type Box:
    value: Int

impl Box:
    fn get() Int: self.value
