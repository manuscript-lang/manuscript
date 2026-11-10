import Closeable from "@std/core.ms"

type Res:
    id: Int

impl Closeable for Res:
    var fn close() Unit!:
        return ok(unit)

enum Holder:
    Has(r: Res)
    Empty

fn dup[T: Clonable](x: T) T:
    return x.clone()

fn f() Int:
    a := Holder.Has(Res(1))
    _b := dup(a)  // error: Holder does not satisfy Clonable
    c: Res? = Res(2)
    _c := dup(c)  // error: Res? does not satisfy Clonable
    return 0
