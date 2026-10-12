# Canonical standard-library declarations. Implementations are native.


export type Result[T, U]:
    case ok(value: T)
    case error(cause: U)
