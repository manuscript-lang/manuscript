// conform: tags=diagnostics
// conform: phase=check
fn choose(value Int) Int {
    return value
}
fn run(fallback Int = choose(1), hook fn(Int) Int) Int {
    box Array[Int] := [choose(3)]
    match fallback {
        Color.Red => {
            return choose(5)
        }
        _ => {
            return choose(6)
        }
    }
}
type Box {
    value Int = choose(7)
}
interface Read {
    fn read(value Int) Int
}
impl Read for Box {
    fn read(value: Int = choose(8)) Int {
        return choose(9)
    }
}
// expect-error: MS1000 23:1-23:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
