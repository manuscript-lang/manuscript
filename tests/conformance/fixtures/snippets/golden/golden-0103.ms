// conform: tags=diagnostics
// conform: phase=check
interface Read[V]:
    fn get() V
type Box[T]:
    value: T
impl Read[U] for Box[U]:
    fn get() U:
        return self.value
