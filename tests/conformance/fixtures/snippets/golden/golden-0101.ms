// conform: tags=diagnostics
// conform: phase=check
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[Int] for Box[Int]:
    fn get() Int:
        return self.value
