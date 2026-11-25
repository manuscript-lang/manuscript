// conform: tags=diagnostics
// conform: phase=check
interface Crash {
    fn run() Int
}
type Item {
    value Int
}
impl Crash for Item {
    fn run() Int {
        return 1 / self.value
    }
}
export fn main() Int {
    item := Item(0)
    run := item.run
    return run()
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
