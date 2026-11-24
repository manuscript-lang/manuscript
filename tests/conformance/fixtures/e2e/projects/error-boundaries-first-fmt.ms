// conform: tags=control-flow,formatter,generics,interfaces,interpolation,modules,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/projects/error_boundaries/first.ms
import DomainFailure, BoxFailure, box_error from "./domain.ms"

export fn first_error(cause DomainFailure) Error:
    return Error(f"first {cause.code}")

fn failure(cause DomainFailure) Void!DomainFailure:
    return error(cause)

export fn first_result(cause DomainFailure) Void!:
    return failure(cause).map_error(first_error)

export fn first_propagated(cause DomainFailure) Void!:
    failure(cause).map_error(first_error)?

fn generic[T](cause T, convert fn(T) Error) Error:
    return convert(cause)

export fn first_generic(cause DomainFailure) Error:
    return generic(cause, first_error)

export fn first_box(cause DomainFailure) Error:
    return box_error(BoxFailure(cause), inner => f"first {inner.code}")
