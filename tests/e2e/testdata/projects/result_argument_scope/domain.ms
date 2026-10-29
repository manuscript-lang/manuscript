export type Cause[T]:
    value: T

export fn make() Cause[Int]: Cause(7)
