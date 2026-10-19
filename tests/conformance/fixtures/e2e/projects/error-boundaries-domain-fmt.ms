# conform: tags=control-flow,formatter,generics,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/domain.ms
export type DomainFailure:
    code: Int

export type BoxFailure[T: Error]:
    cause: T

impl Error for BoxFailure[T]:
    fn message() String:
        return self.cause.message()
