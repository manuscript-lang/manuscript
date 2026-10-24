export type DomainFailure:
    code: Int

export type BoxFailure[T: Error]:
    cause: T

impl Error for BoxFailure[T]:
    def message() -> String:
        return self.cause.message()
