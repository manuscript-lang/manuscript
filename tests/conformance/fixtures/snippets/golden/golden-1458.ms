// conform: tags=diagnostics
// conform: phase=check
interface Counter {
    fn bump(by Int) Int
}
type Cell {
    total Int
}
impl Counter for Cell {
    fn bump(by: Int) Int {
        self.total += by
        return self.total
    }
}
fn probe(value: Int) Int {
    cell := Cell(0)
    cell.bump(value)
    cell.bump(1)
    return cell.total
}
export fn main() Int {
    return probe(9223372036854775807)
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 15:15-15:16 remove the ':' between 'value' and its type; write value Type
// expect-fix: 15:15-15:16 ""
