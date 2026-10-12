# Canonical standard-library declarations. Implementations are native.


export type Result[T, U]:
    case ok(value: T)
    case error(cause: U)

export fn map_error[T, E, F](result: Result[T, E], transform: fn(cause: E) -> F) -> Result[T, F]
