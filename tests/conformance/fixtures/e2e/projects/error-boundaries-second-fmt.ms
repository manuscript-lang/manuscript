# conform: tags=control-flow,formatter,interfaces,interpolation,modules,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/second.ms
import DomainFailure from "./domain.ms"

export fn second_error(cause: DomainFailure) Error:
    return Error("second {cause.code}")

export fn relay(cause: Error) Unit!:
    return error(cause)
