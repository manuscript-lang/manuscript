import Closeable from "@std/core.ms"

type Door:
    n: Int

fn move Door.close() Void!:
    return ok()

interface Taker:
    var fn take(move door: Door) Int

type Counter:
    seen: Int

// Only reads the door it owns: the door closes at the end.
fn var Counter.take(move door: Door) Int:
    self.seen = self.seen + door.n
    return self.seen

fn apply(f: fn(move Door) Int, move door: Door) Int:
    return f(door)

fn wrap(move door: Door) Door?:
    return door

fn f() Int:
    var kept: List[Door] = []
    a := apply(fn move d:
        kept.append(d)
        return kept.length()
    , Door(1))
    maybe: Door? := Door(2)
    b := maybe.map(fn d: wrap(d)).get_or(none).is_some()
    var t: Taker = Counter(0)
    c := t.take(Door(3))
    return a + c + (if b: 1 else: 0)
