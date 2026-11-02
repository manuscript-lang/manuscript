# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/result_bounds_test.go:87 TestSuccessfulResultBoundsRejectDifferentReturns
type Cause:
    text: String

impl Error for Cause:
    fn message() String: self.text.clone()
