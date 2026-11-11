// conform: tags=formatter,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/parser/result_type_test.go:14 TestResultTypeFollowsParametersWithoutArrow
type Box:
    value: Int

fn Box.get() Int: self.value
