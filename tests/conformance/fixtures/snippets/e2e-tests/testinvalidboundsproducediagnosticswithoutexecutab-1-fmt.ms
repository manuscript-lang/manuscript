# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/bound_recovery_test.go:11 TestInvalidBoundsProduceDiagnosticsWithoutExecutable
type Box[Error: Error]:
    cause: Error

impl Error for Box[Error]:
    fn message() String: self.cause.message()

export fn main() Int: 0
