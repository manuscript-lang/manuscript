# conform: tags=control-flow,formatter,interfaces,interpolation,modules,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/second.ms
from "./domain.ms" import DomainFailure

impl Error for DomainFailure:
    def message() -> String:
        return f"second {self.code}"

export def second_error(cause: DomainFailure) -> Error:
    return cause

export def relay(cause: Error) -> Result[Unit, Error]:
    return error(cause)
