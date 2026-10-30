import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit:
        return

type Pair:
    a: Door
    b: Door

fn pair() Pair:
    return Pair(Door(1), Door(2))

fn f() Int:
    let d = pair().a  # error: cannot move `pair(..).a` out of a computed value
    return d.n
