// conform: tags=diagnostics
// conform: phase=check
fn extract[T](value: T?) T:
    return value.get()
export fn main() Int:
    return extract[Int](none)
