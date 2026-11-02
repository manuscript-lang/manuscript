# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=tests/e2e/bound_recovery_test.go:11 TestInvalidBoundsProduceDiagnosticsWithoutExecutable
type Box[Error: Error]:
    cause: Error

impl Error for Box[Error]:
    fn message() String: self.cause.message()

export fn main() Int: 0
