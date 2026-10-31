# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:39 checkInvalidBounds
type Box[Error: Error]:
    cause: Error

impl Error for Box[Error]:
    fn message() String: self.cause.message()
