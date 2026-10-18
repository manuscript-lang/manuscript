import DomainFailure from "./domain.ms"

impl Error for DomainFailure:
    fn message() String:
        return "second {self.code}"

export fn second_error(cause: DomainFailure) Error:
    return cause

export fn relay(cause: Error) Result[Unit, Error]:
    return error(cause)
