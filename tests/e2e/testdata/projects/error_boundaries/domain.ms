export type DomainFailure:
    code: Int

export type BoxFailure[T: Error]:
    cause: T

impl Error for BoxFailure[T]:
    fn message() -> String:
        return self.cause.message()
