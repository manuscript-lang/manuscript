// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn get() Int
type Box[T]:
    value: T
impl Read for Box[Int]:
    fn get() T:
        return self.value
