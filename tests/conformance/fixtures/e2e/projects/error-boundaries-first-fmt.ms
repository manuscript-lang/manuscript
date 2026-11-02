# conform: tags=control-flow,formatter,generics,interfaces,interpolation,modules,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/first.ms
import DomainFailure, BoxFailure, box_error from "./domain.ms"

export fn first_error(cause: DomainFailure) Error:
    return Error("first {cause.code}")

fn failure(cause: DomainFailure) Unit!DomainFailure:
    return error(cause)

export fn first_result(cause: DomainFailure) Unit!:
    return failure(cause).map_error(first_error)

export fn first_propagated(cause: DomainFailure) Unit!:
    try failure(cause).map_error(first_error)
    return ok(unit)

fn generic[T](cause: T, convert: fn(T) Error) Error:
    return convert(cause)

export fn first_generic(cause: DomainFailure) Error:
    return generic(cause, first_error)

export fn first_box(cause: DomainFailure) Error:
    return box_error(BoxFailure(cause), fn inner: "first {inner.code}")
