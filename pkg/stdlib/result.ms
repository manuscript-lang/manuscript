# Canonical standard-library declarations. Implementations are native.

# Holds either a successful value (`ok`) or an expected failure (`error`).
export type Result[T, U]:
    case ok(value: T)
    case error(cause: U)
