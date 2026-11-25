// conform: tags=diagnostics
// conform: phase=check
interface Read {
    fn read() Int
}
type Reader {
    operation fn() Int
}
impl Read for Reader {
    fn read() Int {
        return self.operation()
    }
}
export fn main() Int {
    view := Read(Reader(fn() Int => 1))
    return view.read()
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
