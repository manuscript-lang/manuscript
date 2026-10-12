import Error from "@std/errors.ms"
import Result from "@std/result.ms"
import { DomainFailure, BoxFailure } from "./domain.ms"

impl Error for DomainFailure:
    fn message() -> String:
        return "first {self.code}"

export fn first_error(cause: DomainFailure) -> Error:
    return cause

fn failure(cause: DomainFailure) -> Result[Unit, DomainFailure]:
    return error(cause: cause)

export fn first_result(cause: DomainFailure) -> Result[Unit, Error]:
    return failure(cause)

export fn first_propagated(cause: DomainFailure) -> Result[Unit, Error]:
    let completed = try failure(cause)
    return ok(value: unit)

fn generic[T: Error](cause: T) -> Error:
    return cause

export fn first_generic(cause: DomainFailure) -> Error:
    return generic(cause)

export fn first_box(cause: DomainFailure) -> Error:
    return BoxFailure(cause: cause)
