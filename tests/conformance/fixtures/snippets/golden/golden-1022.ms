// conform: tags=diagnostics
// conform: phase=check
interface Starter {
    fn start(operation fn() Void) Void
}
type Sequential { ... }
impl Starter for Sequential {
    fn start(operation: fn() Void) Void {
        operation()
    }
}
fn run() Void {
    values := [0]
    Sequential().start(fn {
        values.append(1)
    }
    )
}
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 14:27-14:28 a closure without parameter types is written without 'fn': x => { ... }, (a, b) => { ... } or () => { ... }
