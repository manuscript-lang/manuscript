# conform: tags=control-flow,formatter,generics,interfaces,interpolation,modules,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/first.ms
from "./domain.ms" import DomainFailure, BoxFailure

impl Error for DomainFailure:
    def message() -> String:
        return f"first {self.code}"

export def first_error(cause: DomainFailure) -> Error:
    return cause

def failure(cause: DomainFailure) -> Result[Unit, DomainFailure]:
    return error(cause)

export def first_result(cause: DomainFailure) -> Result[Unit, Error]:
    return failure(cause)

export def first_propagated(cause: DomainFailure) -> Result[Unit, Error]:
    try failure(cause)
    return ok(())

def generic[T: Error](cause: T) -> Error:
    return cause

export def first_generic(cause: DomainFailure) -> Error:
    return generic(cause)

export def first_box(cause: DomainFailure) -> Error:
    return BoxFailure(cause)
