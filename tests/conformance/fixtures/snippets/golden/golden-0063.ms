// conform: tags=diagnostics
// conform: phase=check
fn one(value Int) Int {
    return value
}
fn two(left Int, right Int) Int {
    return left - right
}
fn zero() Void {
    return
}
fn identity[T](value T) T {
    return value
}
fn apply(transform fn(Int) Int) Int {
    return transform(1)
}
type Box {
    value Int
}
enum Choice {
    Payload(value Int)
}
interface Read {
    fn get() Int
}
impl Read for Box {
    fn get() Int {
        return self.value
    }
}
// expect-error: MS1000 27:1-27:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
