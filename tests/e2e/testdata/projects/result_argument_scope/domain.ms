export type Cause[T]:
    value: T

export def make() -> Cause[Int]: Cause(7)
