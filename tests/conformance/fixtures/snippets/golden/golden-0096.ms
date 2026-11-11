// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn get() Int
type Box[T]:
    value: T
impl Read for Box[fn(Int) Int]:
    fn get() Int:
        return 1
impl Read for Box[fn(Int) Int]:
    fn get() Int:
        return 2
