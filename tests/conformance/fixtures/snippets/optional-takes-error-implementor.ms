# conform: tags=optional,interfaces,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io.ms"
type E1:
    n: Int
impl Error for E1:
    fn message() String: "e{self.n}"
fn f(b: Bool) Error?:
    if b: return E1(7)
    return none
fn g(xs: List[Error?]) Int: xs.length()
export fn main() Int:
    if let e = f(true):
        stdout().write(e.message() + "\n").get()
    stdout().write("{g([E1(1), none])}\n").get()
    return 0
