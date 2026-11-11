// conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/bound_recovery_test.go:39 checkInvalidBounds
interface Named:
    fn name() String

type Box[Named: Named]:
    cause: Named

fn Box[Named].name() String: self.cause.name()
