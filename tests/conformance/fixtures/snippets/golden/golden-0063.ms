// conform: tags=diagnostics
// conform: phase=check
fn one(value: Int) Int:
    return value
fn two(left: Int, right: Int) Int:
    return left - right
fn zero() Unit:
    return
fn identity[T](value: T) T:
    return value
fn apply(transform: fn(Int) Int) Int:
    return transform(1)
type Box:
    value: Int
enum Choice:
    Payload(value: Int)
interface Read:
    fn get() Int
impl Read for Box:
    fn get() Int:
        return self.value
