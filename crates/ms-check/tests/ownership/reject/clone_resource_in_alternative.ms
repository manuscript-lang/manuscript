import Closeable from "@std/core.ms"

type Res:
    id: Int

impl Closeable for Res:
    var fn close() Unit:
        return

type Holder:
    case Has(r: Res)
    case Empty

fn dup[T: Clonable](x: T) T:
    return x.clone()

fn f() Int:
    let a = Holder.Has(Res(1))
    let _b = dup(a)  # error: Holder does not satisfy Clonable
    let _c = dup(some(Res(2)))  # error: Optional[Res] does not satisfy Clonable
    return 0
