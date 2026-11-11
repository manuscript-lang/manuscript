// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
    none
    T
impl T?:
    fn get() T: ...
