// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
    T
    none
fn wrong(value: Int?) Int:
    return value.get()
