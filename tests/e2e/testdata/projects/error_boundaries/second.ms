from "./domain.ms" import DomainFailure

impl Error for DomainFailure:
    def message() -> String:
        return f"second {self.code}"

export def second_error(cause: DomainFailure) -> Error:
    return cause

export def relay(cause: Error) -> Result[Unit, Error]:
    return error(cause)
