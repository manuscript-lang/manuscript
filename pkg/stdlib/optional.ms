# Canonical standard-library declarations. Implementations are native.

export type Optional[T]:
    case some(value: T)
    case none
    fn is_some() -> Bool
    fn is_none() -> Bool
    fn unwrap() -> T
    fn unwrap_or(fallback: T) -> T
    fn unwrap_or_else(create: fn() -> T) -> T

# Private native implementations shared by the receiver operations.
fn is_some[T](value: Optional[T]) -> Bool
fn is_none[T](value: Optional[T]) -> Bool
fn unwrap[T](value: Optional[T]) -> T
fn unwrap_or[T](value: Optional[T], fallback: T) -> T
fn unwrap_or_else[T](value: Optional[T], create: fn() -> T) -> T
