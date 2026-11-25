// conform: tags=diagnostics
// conform: phase=check
interface Diagnostic {
    fn message() String
}
type LocalError {
    detail String
}
impl Diagnostic for LocalError {
    fn message() String {
        return self.detail
    }
}
fn wrong(value: LocalError) Diagnostic {
    return value
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 14:15-14:16 remove the ':' between 'value' and its type; write value Type
// expect-fix: 14:15-14:16 ""
