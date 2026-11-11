// conform: tags=diagnostics
// conform: phase=check
type B[T]:
    x: T
impl B:
    fn f() Int:
        return 1
