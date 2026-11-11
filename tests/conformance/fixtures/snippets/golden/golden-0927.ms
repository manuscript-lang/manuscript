// conform: tags=diagnostics
// conform: phase=check
export interface Read[T: Equal]:
    fn get() T
type Box[T]:
    value: T
impl Read[T] for Box[T]:
    fn get() T:
        return self.value
