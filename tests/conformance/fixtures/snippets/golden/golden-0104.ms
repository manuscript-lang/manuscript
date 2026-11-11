// conform: tags=diagnostics
// conform: phase=check
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[T] for Box[Int]:
    fn get() T:
        return self.value
