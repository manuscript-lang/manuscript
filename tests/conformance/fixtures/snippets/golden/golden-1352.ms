// conform: tags=diagnostics
// conform: phase=check
type Point {
    x Int
    y Int
}

fn bump(map Int, key Int, step Int = 1) Int => map + key + step

type Counter {
    total Int
}

interface Adder {
    fn add(amount Int, extra Int) Int
}

impl Adder for Counter {
    fn add(amount: Int, extra: Int) Int => self.total + amount + extra
}

fn use(map: Int, key: Int, y: Int, x: Int, counter: Counter) Int { ... }
// expect-error: MS1000 18:1-18:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 22:11-22:12 remove the ':' between 'map' and its type; write map Type
// expect-fix: 22:11-22:12 ""
