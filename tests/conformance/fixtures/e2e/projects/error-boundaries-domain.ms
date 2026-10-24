# conform: tags=control-flow,diagnostics,generics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/error_boundaries/domain.ms
export type DomainFailure:
    code: Int

export type BoxFailure[T: Error]:
    cause: T

impl Error for BoxFailure[T]:
    def message() -> String:
        return self.cause.message()
