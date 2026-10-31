import DomainFailure, BoxFailure from "./domain.ms"

impl Error for DomainFailure:
    fn message() String:
        return "first {self.code}"

export fn first_error(cause: DomainFailure) Error:
    return cause

fn failure(cause: DomainFailure) Unit!DomainFailure:
    return error(cause)

export fn first_result(cause: DomainFailure) Unit!:
    return failure(cause)

export fn first_propagated(cause: DomainFailure) Unit!:
    try failure(cause)
    return ok(unit)

fn generic[T: Error](cause: T) Error:
    return cause

export fn first_generic(cause: DomainFailure) Error:
    return generic(cause)

export fn first_box(cause: DomainFailure) Error:
    return BoxFailure(cause)
