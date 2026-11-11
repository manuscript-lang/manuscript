// conform: tags=diagnostics
// conform: phase=check
interface I:
    fn n() Int
type Pair[A, B]:
    a: A
    b: B
impl I for Pair[A, A]:
    fn n() Int:
        return 1
export fn main() Int:
    return I(value: Pair[Int, String](a: 1, b: "x")).n()
