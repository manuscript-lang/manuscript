# conform: tags=control-flow,diagnostics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/error_boundaries/second.ms
from "./domain.ms" import DomainFailure

impl Error for DomainFailure:
    def message() -> String:
        return f"second {self.code}"

export def second_error(cause: DomainFailure) -> Error:
    return cause

export def relay(cause: Error) -> Result[Unit, Error]:
    return error(cause)
