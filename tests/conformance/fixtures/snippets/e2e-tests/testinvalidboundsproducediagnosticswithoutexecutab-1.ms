// conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
// conform: phase=check
// conform: origin=tests/e2e/bound_recovery_test.go:11 TestInvalidBoundsProduceDiagnosticsWithoutExecutable
interface Named:
    fn name() String

type Box[Named: Named]:
    cause: Named

fn Box[Named].name() String: self.cause.name()

export fn main() Int: 0
