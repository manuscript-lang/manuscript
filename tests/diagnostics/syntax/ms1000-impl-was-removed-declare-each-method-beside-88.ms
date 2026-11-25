// conform: tags=diagnostics
// conform: phase=check
interface Reader {
    fn read() String
}
type Box {
    label String
}
impl Reader for Box {
    fn read() String {
        return self.label
    }
}
fn message(value: Reader) String {
    return value.read()
}
fn make() Box {
    return Box(label: "value")
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 14:17-14:18 remove the ':' between 'value' and its type; write value Type
// expect-fix: 14:17-14:18 ""
