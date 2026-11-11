import Closeable from "@std/core.ms"

type Door:
    n: Int

fn var Door.close() Unit!:
    return ok(unit)

type Pair:
    a: Door
    b: Door

fn pair() Pair:
    return Pair(Door(1), Door(2))

fn f() Int:
    d := pair().a  // error: cannot move `pair(..).a` out of a computed value
    return d.n
