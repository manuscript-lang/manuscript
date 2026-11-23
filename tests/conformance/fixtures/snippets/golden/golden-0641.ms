// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
    T
    null
fn wrong(value: Int?) Int:
    return value.get()
