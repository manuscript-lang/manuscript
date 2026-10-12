# Canonical standard-library declarations. Implementations are native.

export type Optional[T]:
    case some(value: T)
    case none
    fn is_some() -> Bool:
    fn is_none() -> Bool:
    fn unwrap() -> T:
    fn unwrap_or(fallback: T) -> T:
    fn unwrap_or_else(create: fn() -> T) -> T:
