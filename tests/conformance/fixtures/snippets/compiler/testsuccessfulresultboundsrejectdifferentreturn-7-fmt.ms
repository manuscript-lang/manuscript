# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:87 TestSuccessfulResultBoundsRejectDifferentReturns
type Cause:
    text: String

interface Named:
    fn name() String

impl Named for Cause:
    fn name() String: self.text.clone()
