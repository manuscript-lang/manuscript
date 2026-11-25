// conform: tags=diagnostics
// conform: phase=check
interface Add {
    fn add(value Int) Int
}
type Offset {
    value Int
}
impl Add for Offset {
    fn add(value: Int = self.value) Int {
        return value
    }
}
fn call(value: Add) Int {
    return value.add()
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 14:14-14:15 remove the ':' between 'value' and its type; write value Type
// expect-fix: 14:14-14:15 ""
