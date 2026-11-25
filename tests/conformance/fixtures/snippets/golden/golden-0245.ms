// conform: tags=diagnostics
// conform: phase=check
enum Optional[T] {
    T
    null
}

impl T? {
    fn is_some() Bool { ... }
    fn is_none() Bool { ... }
    fn get(default: T? = null) T { ... }
    fn map[U](transform: fn(T) U) U? { ... }
    fn and_then[U](transform: fn(T) U?) U? { ... }
    fn or_else(create: fn() T?) T? { ... }
    fn ok_or[E: Error = MissingValue](cause: E? = null) Result[T, E] { ... }
    fn ok_or_else[E: Error](create: fn() E) Result[T, E] { ... }
}
