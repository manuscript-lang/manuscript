// conform: tags=diagnostics
// conform: phase=check
type Box[T] {
    item T
}
impl Error for Box[T] {
    fn message() String {
        return "box"
    }
}
fn wrong(cause: Error) String {
    match cause {
        Box(value) => {
            return value.message()
        }
        _ => {
            return cause.message()
        }
    }
}
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 11:15-11:16 remove the ':' between 'cause' and its type; write cause Type
// expect-fix: 11:15-11:16 ""
