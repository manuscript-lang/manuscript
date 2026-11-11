// conform: tags=diagnostics
// conform: phase=check
interface Read[V]:
    fn get() V
type Pair[A, B]:
    left: A
    right: B
impl Read[B] for Pair[Int, B]:
    fn get() B:
        return self.right
