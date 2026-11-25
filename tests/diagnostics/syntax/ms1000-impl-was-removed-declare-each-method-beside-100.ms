// conform: tags=diagnostics
// conform: phase=check
import Closeable from "@std/cleanup.ms"
type AggregateResource {
    visits List[Int]
}
impl Closeable for AggregateResource {
    fn close() Void {
        self.visits.append(1)
    }
}
interface AggregateCounter {
    fn bump(by: Int) Int
    fn lower(by: Int) Int
}
type AggregateCell {
    total: Int
}
impl AggregateCounter for AggregateCell {
    fn bump(by: Int) Int {
        self.total += by
        return self.total
    }
    fn lower(by: Int) Int {
        self.total -= by
        return self.total
    }
}
fn identity[T](value: T) T => return value
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 13:15-13:16 remove the ':' between 'by' and its type; write by Type
// expect-fix: 13:15-13:16 ""
// expect-error: MS1000 17:10-17:11 remove the ':' between 'total' and its type; write total Type
// expect-fix: 17:10-17:11 ""
// expect-error: MS1000 19:1-19:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 29:21-29:22 remove the ':' between 'value' and its type; write value Type
// expect-fix: 29:21-29:22 ""
