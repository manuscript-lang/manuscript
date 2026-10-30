# conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/error_boundaries/first.ms
import DomainFailure, BoxFailure from "./domain.ms"

impl Error for DomainFailure:
    fn message() String:
        return "first {self.code}"

export fn first_error(cause: DomainFailure) Error:
    return cause

fn failure(cause: DomainFailure) Result[Unit, DomainFailure]:
    return error(cause)

export fn first_result(cause: DomainFailure) Result[Unit, Error]:
    return failure(cause)

export fn first_propagated(cause: DomainFailure) Result[Unit, Error]:
    try failure(cause)
    return ok(unit)

fn generic[T: Error](cause: T) Error:
    return cause

export fn first_generic(cause: DomainFailure) Error:
    return generic(cause)

export fn first_box(cause: DomainFailure) Error:
    return BoxFailure(cause)
