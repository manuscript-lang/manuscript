// conform: tags=diagnostics
// conform: phase=check
interface Counter {
    fn bump(by Int) Int
    fn lower(by Int) Int
}
type Cell {
    total Int
}
impl Counter for Cell {
    fn bump(by: Int) Int {
        self.total += by
        return self.total
    }
    fn lower(by: Int) Int {
        self.total -= by
        return self.total
    }
}
fn take(value: Cell) Int => return value.total
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 20:14-20:15 remove the ':' between 'value' and its type; write value Type
// expect-fix: 20:14-20:15 ""
