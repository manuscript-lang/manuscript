// conform: tags=diagnostics
// conform: phase=check
enum Optional[T] {
    null
    T
}
impl T? {
    fn get() T { ... }
}
