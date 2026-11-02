# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/bound_recovery_test.go:11 TestInvalidBoundsProduceDiagnosticsWithoutExecutable
interface Named:
    fn name() String

type Box[Named: Named]:
    cause: Named

impl Named for Box[Named]:
    fn name() String: self.cause.name()

export fn main() Int: 0
