import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

type Bag[U]:
    items: List[U]

interface Dup:
    fn dup() Int

impl Dup for Bag[U]:
    fn dup() Int:
        return self.items.take(1).length()  # error: take requires U to be Clonable

fn via[T: Dup](x: T) Int:
    return x.dup()

fn direct(x: Dup) Int:
    return x.dup()

fn g() Int:
    let a = via(Bag([Door(1)]))
    return a + direct(Bag([Door(2)]))
