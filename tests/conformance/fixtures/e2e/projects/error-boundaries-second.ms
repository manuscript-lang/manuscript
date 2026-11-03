# conform: tags=control-flow,diagnostics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/error_boundaries/second.ms
import DomainFailure from "./domain.ms"

export fn second_error(cause: DomainFailure) Error:
    return Error("second {cause.code}")

export fn relay(cause: Error) Unit!:
    return error(cause)
