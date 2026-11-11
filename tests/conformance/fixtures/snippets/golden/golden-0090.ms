// conform: tags=diagnostics
// conform: phase=check
interface Read[T]:
    fn get() T
type Box[T]:
    value: T
impl Read[T] for Box[T]:
    fn get() T:
        return self.value
impl Read[Int] for Box[Int]:
    fn get() Int:
        return self.value
