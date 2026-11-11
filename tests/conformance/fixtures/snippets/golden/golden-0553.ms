// conform: tags=diagnostics
// conform: phase=check
export interface Read[T]:
    fn get() T
export type Box[T]:
    value: T
export fn invoke[T: Read[Int]](value: T) Int:
    return value.get()
