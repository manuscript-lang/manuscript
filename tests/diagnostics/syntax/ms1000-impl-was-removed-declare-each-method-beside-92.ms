// conform: tags=diagnostics
// conform: phase=check
interface Describe {
    fn describe() String
}
enum State {
    Ready
    Waiting
}
impl Describe for State {
    fn describe() String => "state"
}
fn use(value: Describe) Int {
    match value {
        State(Ready) => return 1
        _ => return 0
    }
}
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 13:13-13:14 remove the ':' between 'value' and its type; write value Type
// expect-fix: 13:13-13:14 ""
