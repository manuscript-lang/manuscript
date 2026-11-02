# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:39 checkInvalidBounds
interface Named:
    fn name() String

type Box[Named: Named]:
    cause: Named

impl Named for Box[Named]:
    fn name() String: self.cause.name()
