// conform: tags=diagnostics
// conform: phase=check
interface Read[T]:
    fn get() Int
type Pair[A, B]:
    left: A
    right: B
impl Read[A] for Pair[A, A]:
    fn get() Int:
        return 1
impl Read[A] for Pair[A, List[A]]:
    fn get() Int:
        return 2
